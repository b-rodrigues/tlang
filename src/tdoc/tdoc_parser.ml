(* src/tdoc/tdoc_parser.ml *)
(* Parser for T-Doc comments (--#) *)

open Tdoc_types

let starts_with s prefix =
  String.length s >= String.length prefix &&
  String.sub s 0 (String.length prefix) = prefix

let strip_prefix s prefix =
  if starts_with s prefix then
    String.sub s (String.length prefix) (String.length s - String.length prefix)
  else s

(* Extract --# comments from a file *)
let extract_comments filename =
  let lines = ref [] in
  let chan = open_in filename in
  try
    while true do
      lines := input_line chan :: !lines
    done;
    [] (* unreachable *)
  with End_of_file ->
    close_in chan;
    List.rev !lines

(* Parse a block of comment lines into a doc_entry *)
(* This is a simplified state-machine parser *)
let parse_block lines filename line_num =
  let name_override = ref None in
  let brief = ref "" in
  let full = Buffer.create 1024 in
  let params = ref [] in
  let return_val = ref None in
  let examples = ref [] in
  let see_also = ref [] in
  let family = ref None in
  let is_export = ref false in
  let intent = ref None in
  let current_tag = ref `Brief in
  
  (* Helpers to set state *)
  let add_param line = 
    (* Format: @param <name> :: <type> <desc> OR @param <name> <desc> *)
    let parts = String.split_on_char ' ' (String.trim line) |> List.filter (fun s -> s <> "") in
    match parts with
    | name :: "::" :: type_info :: rest ->
        let desc = String.concat " " rest in
        params := { name; type_info = Some type_info; description = desc } :: !params
    | name :: rest ->
        (* Check if description starts with :: <type> *)
        let desc = String.concat " " rest in
        if starts_with desc ":: " then
          let type_part = try List.nth (String.split_on_char ' ' desc) 1 with _ -> "" in
          let real_desc = try 
            let parts = String.split_on_char ' ' desc in
            String.concat " " (List.tl (List.tl parts))
          with _ -> "" in
          params := { name; type_info = Some type_part; description = real_desc } :: !params
        else
          params := { name; type_info = None; description = desc } :: !params
    | [] -> ()
  in

  let add_return line =
    let parts = String.split_on_char ' ' (String.trim line) |> List.filter (fun s -> s <> "") in
    match parts with
    | "::" :: type_info :: rest ->
        let desc = String.concat " " rest in
        return_val := Some { type_info = Some type_info; description = desc }
    | _ ->
        (* Check if line starts with :: without space or something? No, split handles it if space exists *)
        (* Maybe the user wrote @return ::Type ... *)
        return_val := Some { type_info = None; description = String.trim line }
  in

  List.iter (fun line ->
    let clean_line = String.trim line in
    if starts_with clean_line "@param" then (current_tag := `Param; add_param (strip_prefix clean_line "@param"))
    else if starts_with clean_line "@return" then (current_tag := `Return; add_return (strip_prefix clean_line "@return"))
    else if starts_with clean_line "@example" then (current_tag := `Example)
    else if starts_with clean_line "@seealso" then (
      let items = String.split_on_char ',' (strip_prefix clean_line "@seealso") in
      see_also := List.map String.trim items @ !see_also
    )
    else if starts_with clean_line "@family" then family := Some (String.trim (strip_prefix clean_line "@family"))
    else if starts_with clean_line "@export" then is_export := true
    else if starts_with clean_line "@intent" then current_tag := `Intent
    else if starts_with clean_line "@name" then name_override := Some (String.trim (strip_prefix clean_line "@name"))
    else (
      (* Content continuation based on current tag *)
      match !current_tag with
      | `Brief -> 
          if !brief = "" then brief := clean_line 
          else (current_tag := `Full; Buffer.add_string full clean_line; Buffer.add_char full ' ')
      | `Full -> Buffer.add_string full clean_line; Buffer.add_char full ' '
      | `Example -> examples := clean_line :: !examples (* Reverse order, fix later *)
      | _ -> () (* Ignore others for now *)
    )
  ) lines;

  {
    name = (match !name_override with Some n -> n | None -> "unknown");
    description_brief = !brief;
    description_full = String.trim (Buffer.contents full);
    params = List.rev !params;
    return_value = !return_val;
    examples = List.rev !examples;
    see_also = List.rev !see_also;
    family = !family;
    is_export = !is_export;
    intent = !intent;
    package = None;
    source_path = filename;
    line_number = line_num;
  }

(* Scan a file for T-Doc blocks *)
let parse_file filename =
  let lines = extract_comments filename in
  let blocks = ref [] in
  let current_block = ref [] in
  let inside_block = ref false in
  let start_line = ref 0 in
  
  List.iteri (fun i line ->
    let trimmed = String.trim line in
    if starts_with trimmed "--#" then begin
      if not !inside_block then (inside_block := true; start_line := i + 1);
      let content = strip_prefix trimmed "--#" in
      current_block := content :: !current_block
    end else begin
      if !inside_block then begin
        (* End of block *)
        (* Try to infer name from the current line (which is the first line of code after the block) *)
        let inferred_name =
          (* Normalize common prefixes like "export ", "pub ", "test " before inferring the name *)
          let code_line =
            let prefixes = ["export "; "pub "; "test "] in
            List.fold_left
              (fun acc prefix ->
                if starts_with acc prefix then strip_prefix acc prefix else acc
              )
              trimmed
              prefixes
          in
          if starts_with code_line "let " then
            try
              let parts = String.split_on_char ' ' code_line in
              List.nth parts 1
            with _ -> "unknown"
          else if starts_with code_line "fn " then
            try
              let parts = String.split_on_char ' ' code_line in
              let name_part = List.nth parts 1 in
              (* Handle fn name(...) *)
              List.hd (String.split_on_char '(' name_part)
            with _ -> "unknown"
          else "unknown"
        in
        
        let doc = parse_block (List.rev !current_block) filename !start_line in
        let final_name = if doc.name <> "unknown" then doc.name else inferred_name in
        blocks := { doc with name = final_name } :: !blocks;
        current_block := [];
        inside_block := false
      end
    end
  ) lines;
  
  if !inside_block then begin
     let doc = parse_block (List.rev !current_block) filename !start_line in
     blocks := { doc with name = "unknown" } :: !blocks
  end;
  
  List.rev !blocks
