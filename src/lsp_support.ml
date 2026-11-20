(* src/lsp_support.ml *)
(* Pure, testable LSP helpers: static diagnostics, quick-fix edits, and live
   artifact hover from _pipeline/ build logs and foreign_meta sidecars. *)

type text_edit = {
  start_line : int;
  start_char : int;
  end_line : int;
  end_char : int;
  new_text : string;
}

type quick_fix = {
  qf_title : string;
  qf_edits : text_edit list;
}

let uri_to_file_path uri_str =
  let prefix = "file://" in
  let raw =
    if String.starts_with ~prefix uri_str then
      String.sub uri_str (String.length prefix) (String.length uri_str - String.length prefix)
    else uri_str
  in
  (* Decode %20 spaces in file URIs *)
  let buf = Buffer.create (String.length raw) in
  let n = String.length raw in
  let rec loop i =
    if i >= n then ()
    else if raw.[i] = '%' && i + 2 < n && raw.[i + 1] = '2' && raw.[i + 2] = '0' then begin
      Buffer.add_char buf ' ';
      loop (i + 3)
    end else begin
      Buffer.add_char buf raw.[i];
      loop (i + 1)
    end
  in
  loop 0;
  Buffer.contents buf

(* Convert a byte offset in [text] into 0-based (line, character) for LSP. *)
let offset_to_line_char text offset =
  let n = min (max 0 offset) (String.length text) in
  let line = ref 0 in
  let line_start = ref 0 in
  for i = 0 to n - 1 do
    if text.[i] = '\n' then begin
      incr line;
      line_start := i + 1
    end
  done;
  (!line, n - !line_start)

let static_diagnostics_of_text ~filename text : Diagnostics.diagnostic list =
  let lexbuf = Lexing.from_string text in
  lexbuf.Lexing.lex_curr_p <- { lexbuf.Lexing.lex_curr_p with pos_fname = filename };
  try
    let program = Parser.program Lexer.token lexbuf in
    Check_utils.dead_inspect_diagnostics program filename
    @ Check_utils.read_log_string_diagnostics program filename
  with
  | Ast.Invalid_type_declaration (msg, pos_opt) ->
      let pos =
        match pos_opt with
        | Some p -> p
        | None -> Lexing.lexeme_start_p lexbuf
      in
      let loc : Ast.source_location = {
        file = Some filename;
        line = pos.Lexing.pos_lnum;
        column = pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1;
      } in
      let err_info : Ast.error_info = {
        code = Ast.SyntaxError;
        message = msg;
        context = [];
        location = Some loc;
        na_count = 0;
      } in
      [Diagnostics.of_verror ~file:filename err_info]
  | _ -> []

let diag_overlaps_lines ~range_start_line ~range_end_line (d : Diagnostics.diagnostic) =
  match d.diag_line with
  | None -> true
  | Some l ->
      let l0 = max 0 (l - 1) in
      l0 >= range_start_line && l0 <= range_end_line

let quick_fixes_for_range ~text ~range_start_line ~range_end_line (diags : Diagnostics.diagnostic list) : quick_fix list =
  let seen = Hashtbl.create 8 in
  List.filter_map (fun (d : Diagnostics.diagnostic) ->
    if not (diag_overlaps_lines ~range_start_line ~range_end_line d) then None
    else
      match d.diag_suggested_fix with
      | Diagnostics.Replace_text { old_text; new_text; line; column; _ } ->
          let positions = Fix.replace_positions ~content:text ~old_text ~line ?column () in
          (match positions with
           | [] -> None
           | _ ->
               let title = Printf.sprintf "Replace '%s' with '%s'" old_text new_text in
               let key = Printf.sprintf "rt:%s:%s:%d" title (String.concat "," (List.map string_of_int positions)) (List.length positions) in
               if Hashtbl.mem seen key then None
               else begin
                 Hashtbl.add seen key ();
                 let m = String.length old_text in
                 let edits =
                   List.map (fun pos ->
                     let (sl, sc) = offset_to_line_char text pos in
                     let (el, ec) = offset_to_line_char text (pos + m) in
                     { start_line = sl; start_char = sc; end_line = el; end_char = ec; new_text }
                   ) positions
                 in
                 Some { qf_title = title; qf_edits = edits }
               end)
      | Diagnostics.Rename_column { old_name; new_name; line; _ } ->
          let old_text = "$" ^ old_name in
          let new_text = "$" ^ new_name in
          let positions = Fix.replace_positions ~content:text ~old_text ~line () in
          (match positions with
           | [] -> None
           | _ ->
               let title = Printf.sprintf "Rename column '$%s' to '$%s'" old_name new_name in
               let key = "rc:" ^ title in
               if Hashtbl.mem seen key then None
               else begin
                 Hashtbl.add seen key ();
                 let m = String.length old_text in
                 let edits =
                   List.map (fun pos ->
                     let (sl, sc) = offset_to_line_char text pos in
                     let (el, ec) = offset_to_line_char text (pos + m) in
                     { start_line = sl; start_char = sc; end_line = el; end_char = ec; new_text }
                   ) positions
                 in
                 Some { qf_title = title; qf_edits = edits }
               end)
      | _ -> None
  ) diags

(* Extract (target, field) when cursor is on [field] in `target.field`. *)
let extract_dot_member line_text character =
  let line_len = String.length line_text in
  if line_len = 0 then None
  else
    let clamped = max 0 (min character (line_len - 1)) in
    if not (Lexer.is_ident_char line_text.[clamped]) then None
    else
      let rec find_start idx =
        if idx < 0 || not (Lexer.is_ident_char line_text.[idx]) then idx + 1
        else find_start (idx - 1)
      in
      let rec find_end idx =
        if idx >= line_len || not (Lexer.is_ident_char line_text.[idx]) then idx
        else find_end (idx + 1)
      in
      let field_start = find_start clamped in
      let field_end = find_end clamped in
      if field_start < 2 || line_text.[field_start - 1] <> '.' then None
      else
        let target_end = field_start - 1 in
        if not (Lexer.is_ident_char line_text.[target_end - 1]) then None
        else
          let target_start = find_start (target_end - 1) in
          let target = String.sub line_text target_start (target_end - target_start) in
          let field = String.sub line_text field_start (field_end - field_start) in
          Some (target, field)

let read_small_file path =
  try
    let ch = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
      let n = in_channel_length ch in
      if n > 1048576 then None
      else Some (really_input_string ch n))
  with Sys_error _ -> None

let assoc_str key pairs =
  match List.assoc_opt key pairs with
  | Some (`String s) when String.trim s <> "" -> Some (String.trim s)
  | _ -> None

let format_meta_lines meta_pairs =
  let lines = ref [] in
  let add s = lines := s :: !lines in
  (match assoc_str "kind" meta_pairs, assoc_str "task" meta_pairs with
   | Some k, Some t -> add (Printf.sprintf "- **Kind**: `%s` (`%s`)" k t)
   | Some k, None -> add (Printf.sprintf "- **Kind**: `%s`" k)
   | None, Some t -> add (Printf.sprintf "- **Task**: `%s`" t)
   | None, None -> ());
  (match assoc_str "method" meta_pairs with
   | Some m -> add (Printf.sprintf "- **Method**: `%s`" m)
   | None -> ());
  (match List.assoc_opt "n_obs" meta_pairs with
   | Some (`Int n) -> add (Printf.sprintf "- **Observations**: `%d`" n)
   | _ -> ());
  (match List.assoc_opt "columns" meta_pairs with
   | Some (`List cols) ->
       let names = List.filter_map (function `String s -> Some s | _ -> None) cols in
       if names <> [] then
         let total = List.length names in
         let preview =
           if total <= 8 then String.concat ", " names
           else
             let rec take k acc = function
               | [] -> List.rev acc
               | _ when k <= 0 -> List.rev acc
               | x :: xs -> take (k - 1) (x :: acc) xs
             in
             String.concat ", " (take 8 [] names) ^ Printf.sprintf ", ... (+%d more)" (total - 8)
         in
         add (Printf.sprintf "- **Columns (%d)**: `%s`" total preview)
   | _ -> ());
  (match List.assoc_opt "metrics" meta_pairs with
   | Some (`Assoc ms) ->
       let parts =
         List.filter_map (fun (k, v) ->
           match v with
           | `Float f -> Some (Printf.sprintf "%s=%.4g" k f)
           | `Int i -> Some (Printf.sprintf "%s=%d" k i)
           | _ -> None
         ) ms
       in
       if parts <> [] then
         add (Printf.sprintf "- **Metrics**: `%s`" (String.concat ", " parts))
   | _ -> ());
  List.rev !lines

let find_node_entry_in_dir ~pipeline_dir ~node_name =
  match Schema_check.latest_build_log_in_dir pipeline_dir with
  | None -> None
  | Some log_path ->
      (match read_small_file log_path with
       | None -> None
       | Some raw ->
           (try
              match Yojson.Safe.from_string raw with
              | `Assoc pairs ->
                  (match List.assoc_opt "nodes" pairs with
                   | Some (`List nodes) ->
                       List.find_map (function
                         | `Assoc entry ->
                             (match assoc_str "node" entry with
                              | Some nm when nm = node_name -> Some entry
                              | _ -> None)
                         | _ -> None
                       ) nodes
                   | _ -> None)
              | _ -> None
            with Yojson.Json_error _ -> None))

let artifact_hover_markdown ~file_path ~node_name : string option =
  let candidate_dirs =
    let dir = Filename.dirname file_path in
    let parent = Filename.dirname dir in
    [
      Filename.concat dir "_pipeline";
      Filename.concat parent "_pipeline";
      "_pipeline";
    ]
  in
  match List.find_map (fun d -> find_node_entry_in_dir ~pipeline_dir:d ~node_name) candidate_dirs with
  | None -> None
  | Some entry ->
      let status = Option.value ~default:"Unknown" (assoc_str "status" entry) in
      let runtime = Option.value ~default:"T" (assoc_str "runtime" entry) in
      let serializer = Option.value ~default:"default" (assoc_str "serializer" entry) in
      let klass = assoc_str "class" entry in
      let path = assoc_str "path" entry in
      let err_msg = assoc_str "error_message" entry in
      let lines = ref [
        Printf.sprintf "**Pipeline Node `%s`**" node_name;
        "";
        Printf.sprintf "- **Status**: `%s` | **Runtime**: `%s` | **Serializer**: `%s`" status runtime serializer;
      ] in
      (match klass with
       | Some c -> lines := !lines @ [Printf.sprintf "- **Class**: `%s`" c]
       | None -> ());
      (match err_msg with
       | Some m -> lines := !lines @ [Printf.sprintf "- **Error**: %s" m]
       | None -> ());
      (match path with
       | Some p ->
           let meta_path =
             try
               if Sys.file_exists p && Sys.is_directory p then Filename.concat p "meta"
               else Filename.concat (Filename.dirname p) "meta"
             with Sys_error _ -> ""
           in
           if meta_path <> "" && (try Sys.file_exists meta_path with Sys_error _ -> false) then
             (match read_small_file meta_path with
              | Some raw ->
                  (try
                     match Yojson.Safe.from_string raw with
                     | `Assoc mp -> lines := !lines @ format_meta_lines mp
                     | _ -> ()
                   with Yojson.Json_error _ -> ())
              | None -> ())
       | None -> ());
      Some (String.concat "\n" !lines)
