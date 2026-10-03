(* src/tdoc/tdoc_parser.ml *)
(* Parser for T-Doc comments (--#) *)

open Tdoc_types

(** Check if a string starts with a given prefix.
    
    @param s The main string.
    @param prefix The prefix to check for.
    @return [true] if it starts with the prefix, otherwise [false]. *)
let starts_with s prefix =
  String.length s >= String.length prefix &&
  String.sub s 0 (String.length prefix) = prefix

(** Strip a prefix from a string if it is present.
    
    @param s The main string.
    @param prefix The prefix to strip.
    @return The string without the prefix, or the original string if the prefix was not found. *)
let strip_prefix s prefix =
  if starts_with s prefix then
    String.sub s (String.length prefix) (String.length s - String.length prefix)
  else s

(** Extract all comment/code lines from a source file.
    
    @param filename The path to the source file.
    @return A list of all lines in the file. *)
let extract_comments filename =
  let lines = ref [] in
  try
    let chan = open_in filename in
    Fun.protect
      ~finally:(fun () -> close_in_noerr chan)
      (fun () ->
        try
          while true do
            lines := input_line chan :: !lines
          done
        with End_of_file -> ());
    List.rev !lines
  with
  | Sys_error msg ->
      Printf.eprintf "Warning: Could not read file '%s': %s\n%!" filename msg;
      []
  | Out_of_memory | Stack_overflow as e -> raise e

(** Parse a raw list of `--#` T-Doc comment lines into a structured documentation entry.
    
    @param lines The list of comment line contents.
    @param filename The source file path.
    @param line_num The start line number.
    @return A populated [doc_entry] record. *)
let parse_block lines filename line_num =
  let name_override = ref None in
  let brief = ref "" in
  let full = Buffer.create 1024 in
  let params = ref [] in
  let return_val = ref None in
  let examples = ref [] in
  let see_also = ref [] in
  let family = ref None in
  let is_export = ref true in
  let intent = ref None in
  let current_tag = ref `Brief in
  
  (* Helpers to set state *)
  (* Join whitespace-split tokens back into one type while brackets stay
     open, so `Dict[String, Dict]` survives as a single type instead of
     truncating to `Dict[String,`. A `|` token continues the union
     (`Dict | List`), so spaced unions parse whole instead of keeping
     only the first member. Returns the type and the rest. *)
  let join_bracketed toks =
    let depth s =
      String.fold_left (fun d c ->
        match c with
        | '[' | '(' | '<' -> d + 1
        | ']' | ')' | '>' -> d - 1
        | _ -> d
      ) 0 s
    in
    let rec loop acc d = function
      | [] -> (String.concat " " (List.rev acc), [])
      | t :: rest ->
          let d' = d + depth t in
          if d' <= 0 then (String.concat " " (List.rev (t :: acc)), rest)
          else loop (t :: acc) d' rest
    in
    match toks with
    | [] -> ("", [])
    | t :: rest ->
        if depth t <= 0 then (t, rest)
        else loop [t] (depth t) rest
  in
  let rec join_type toks =
    match join_bracketed toks with
    | ("", rest) -> ("", rest)
    | (head, "|" :: more) when more <> [] ->
        let (tail, rest) = join_type more in
        if tail = "" then (head, rest)
        else (head ^ " | " ^ tail, rest)
    | done_ -> done_
  in
  let add_param line =
    (* Format: @param <name> :: <type> <desc> OR @param <name> <desc> *)
    let parts = String.split_on_char ' ' (String.trim line) |> List.filter (fun s -> s <> "") in
    match parts with
    | name :: "::" :: type_toks ->
        let (type_info, rest) = join_type type_toks in
        let desc = String.concat " " rest in
        params := { name; type_info = Some type_info; description = desc } :: !params
    | name :: rest ->
        let desc = String.concat " " rest in
        if starts_with desc ":: " then
          let parts = String.split_on_char ' ' desc |> List.filter (fun s -> s <> "") in
          (match parts with
           | _ :: type_toks ->
               let (type_part, rest_toks) = join_type type_toks in
               let real_desc = String.concat " " rest_toks in
               params := { name; type_info = Some type_part; description = real_desc } :: !params
           | [] ->
               params := { name; type_info = Some ""; description = "" } :: !params)
        else
          params := { name; type_info = None; description = desc } :: !params
    | [] -> ()
  in

  let add_return line =
    let parts = String.split_on_char ' ' (String.trim line) |> List.filter (fun s -> s <> "") in
    match parts with
    | "::" :: type_toks ->
        let (type_info, rest) = join_type type_toks in
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
    else if starts_with clean_line "@private" then is_export := false
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

  let data_first_params params =
    let is_data_param (p : param_doc) = String.lowercase_ascii p.name = "data" in
    let data_params, other_params = List.partition is_data_param params in
    data_params @ other_params
  in

  {
    name = (match !name_override with Some n -> n | None -> "unknown");
    description_brief = !brief;
    description_full = String.trim (Buffer.contents full);
    params = data_first_params (List.rev !params);
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

(*
--# Parse T-Doc Comments
--#
--# Scans a source file and extracts all T-Doc documentation blocks (lines starting with `--#`).
--# Parses the tags (`@name`, `@param`, `@return`, etc.) into structured documentation entries.
--#
--# @name parse_file
--# @param filename :: String The path to the source file to parse.
--# @return :: List[DocEntry] A list of parsed documentation entries.
--# @family tdoc
--# @export
*)

(** Scan a source file and extract all T-Doc documentation blocks (lines starting with `--#`).
    
    @param filename The path to the source file to parse.
    @return A list of parsed documentation entries. *)
let parse_file filename =
  let lines = extract_comments filename in
  let blocks = ref [] in
  let current_block = ref [] in
  let inside_block = ref false in
  let start_line = ref 0 in
  let close_block current_trimmed =
    (* End of block. Try to infer name from the current line (which is the
       first line of code after the block). *)
    let inferred_name =
      (* Normalize common prefixes like "export ", "pub ", "test " before inferring the name *)
      let code_line =
        let prefixes = ["export "; "pub "; "test "] in
        List.fold_left
          (fun acc prefix ->
            if starts_with acc prefix then strip_prefix acc prefix else acc
          )
          current_trimmed
          prefixes
      in
      if starts_with code_line "let " then
        (match String.split_on_char ' ' code_line with
         | _ :: name :: _ -> name
         | _ -> "unknown")
      else if starts_with code_line "fn " then
        (match String.split_on_char ' ' code_line with
         | _ :: name_part :: _ ->
           (match String.split_on_char '(' name_part with
            | hd :: _ -> hd
            | [] -> "unknown")
         | _ -> "unknown")
      else "unknown"
    in
    let doc = parse_block (List.rev !current_block) filename !start_line in
    let final_name = if doc.name <> "unknown" then doc.name else inferred_name in
    blocks := { doc with name = final_name } :: !blocks;
    current_block := [];
    inside_block := false
  in
  List.iteri (fun i line ->
    let trimmed = String.trim line in
    if starts_with trimmed "--#" then begin
      let content = strip_prefix trimmed "--#" in
      if String.trim content = "*)" then begin
        (* OCaml comment closer: ends the block without becoming content.
           This covers indented blocks (e.g. inside `let register`), whose
           closer line would otherwise leak as an example. *)
        if !inside_block then close_block trimmed
      end else begin
        if not !inside_block then (inside_block := true; start_line := i + 1);
        current_block := content :: !current_block
      end
    end else begin
      if !inside_block then close_block trimmed
    end
  ) lines;
  
  if !inside_block then begin
     let doc = parse_block (List.rev !current_block) filename !start_line in
     blocks := { doc with name = "unknown" } :: !blocks
  end;
  
  List.rev !blocks
