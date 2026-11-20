(* src/lsp_support.ml *)
(* Pure, testable LSP helpers: static diagnostics, quick-fix edits, pipeline
   binding discovery, and live artifact hover from _pipeline/ build logs and
   foreign_meta sidecars. *)

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

let hex_digit = function
  | '0'..'9' as c -> Some (Char.code c - Char.code '0')
  | 'a'..'f' as c -> Some (Char.code c - Char.code 'a' + 10)
  | 'A'..'F' as c -> Some (Char.code c - Char.code 'A' + 10)
  | _ -> None

let uri_to_file_path uri_str =
  let prefix = "file://" in
  let raw =
    if String.starts_with ~prefix uri_str then
      String.sub uri_str (String.length prefix) (String.length uri_str - String.length prefix)
    else uri_str
  in
  let buf = Buffer.create (String.length raw) in
  let n = String.length raw in
  let rec loop i =
    if i >= n then ()
    else if raw.[i] = '%' && i + 2 < n then
      (match hex_digit raw.[i + 1], hex_digit raw.[i + 2] with
       | Some hi, Some lo ->
           Buffer.add_char buf (Char.chr ((hi lsl 4) lor lo));
           loop (i + 3)
       | _ ->
           Buffer.add_char buf raw.[i];
           loop (i + 1))
    else begin
      Buffer.add_char buf raw.[i];
      loop (i + 1)
    end
  in
  loop 0;
  Buffer.contents buf

(* Count UTF-16 code units in [text] from byte [from_idx] up to byte [to_idx].
   LSP positions use UTF-16 code units: 1..3-byte UTF-8 sequences = 1 unit,
   4-byte UTF-8 sequences (supplementary planes) = 2 units (surrogate pair). *)
let utf16_len_between text from_idx to_idx =
  let units = ref 0 in
  let i = ref from_idx in
  while !i < to_idx do
    let b = Char.code text.[!i] in
    if b < 0x80 then begin
      incr units;
      incr i
    end else if b land 0xE0 = 0xC0 then begin
      incr units;
      i := !i + 2
    end else if b land 0xF0 = 0xE0 then begin
      incr units;
      i := !i + 3
    end else if b land 0xF8 = 0xF0 then begin
      units := !units + 2;
      i := !i + 4
    end else begin
      incr units;
      incr i
    end
  done;
  !units

(* Convert a byte offset in [text] into 0-based (line, UTF-16 character) for LSP. *)
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
  (!line, utf16_len_between text !line_start n)

let static_diagnostics_of_program ~filename (program : Ast.program) : Diagnostics.diagnostic list =
  Check_utils.dead_inspect_diagnostics program filename
  @ Check_utils.read_log_string_diagnostics program filename

let diagnostic_of_invalid_type_decl ~filename msg (pos : Lexing.position) : Diagnostics.diagnostic =
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
  Diagnostics.of_verror ~file:filename err_info

let static_diagnostics_of_text ~filename text : Diagnostics.diagnostic list =
  let lexbuf = Lexing.from_string text in
  lexbuf.Lexing.lex_curr_p <- { lexbuf.Lexing.lex_curr_p with pos_fname = filename };
  try
    let program = Parser.program Lexer.token lexbuf in
    static_diagnostics_of_program ~filename program
  with
  | Ast.Invalid_type_declaration (msg, pos_opt) ->
      let pos =
        match pos_opt with
        | Some p -> p
        | None -> Lexing.lexeme_start_p lexbuf
      in
      [diagnostic_of_invalid_type_decl ~filename msg pos]
  | _ -> []

(* Collect variable names bound to pipelines in a parsed program so hover only
   treats `p.node` as a pipeline node when `p` is actually a pipeline binding. *)
let pipeline_bindings_of_program (program : Ast.program) : string list =
  let pipeline_producing_fns = [
    "build_pipeline"; "populate_pipeline"; "pipeline_copy"; "filter_node";
    "mutate_node"; "rename_node"; "select_node"; "arrange_node"; "expand_pipeline";
    "set_pipeline_global_options"; "union"; "difference"; "intersect"; "patch";
    "swap"; "rewire"; "prune"; "upstream_of"; "downstream_of"; "subgraph";
    "chain"; "parallel"; "meta_flatten";
  ] in
  let is_pipeline_expr (e : Ast.expr) =
    match e.Ast.node with
    | Ast.PipelineDef _ | Ast.PipelineOfDef _ -> true
    | Ast.Call { fn = { Ast.node = Ast.Var fn_name; _ }; _ } ->
        List.mem fn_name pipeline_producing_fns
    | _ -> false
  in
  let names = ref [] in
  List.iter (fun (s : Ast.stmt) ->
    match s.Ast.node with
    | Ast.Assignment { name; expr; _ } when is_pipeline_expr expr ->
        if not (List.mem name !names) then names := name :: !names
    | _ -> ()
  ) program;
  List.rev !names

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
      | _ -> None
  ) diags

let is_ident_start = function
  | 'a'..'z' | 'A'..'Z' | '_' -> true
  | _ -> false

(* Check whether byte index [pos] in [line_text] is inside a string literal
   or after a `--` line comment. *)
let in_string_or_comment line_text pos =
  let n = min pos (String.length line_text) in
  let in_str = ref false in
  let in_comment = ref false in
  let i = ref 0 in
  while !i < n && not !in_comment do
    let c = line_text.[!i] in
    if !in_str then begin
      if c = '\\' && !i + 1 < n then i := !i + 2
      else begin
        if c = '"' then in_str := false;
        incr i
      end
    end else if c = '"' then begin
      in_str := true;
      incr i
    end else if c = '-' && !i + 1 < n && line_text.[!i + 1] = '-' then begin
      in_comment := true
    end else incr i
  done;
  !in_str || !in_comment

(* Extract (target, field) when cursor is on [field] in `target.field`,
   rejecting numeric literals (e.g. 1.5), comments, and string literals. *)
let extract_dot_member line_text character =
  let line_len = String.length line_text in
  if line_len = 0 then None
  else
    let clamped = max 0 (min character (line_len - 1)) in
    if in_string_or_comment line_text clamped then None
    else if not (Lexer.is_ident_char line_text.[clamped]) then None
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
          if not (is_ident_start target.[0]) || not (is_ident_start field.[0]) then None
          else Some (target, field)

let format_meta_lines meta_pairs =
  let lines = ref [] in
  let add s = lines := s :: !lines in
  (match Artifact_meta.assoc_str "kind" meta_pairs, Artifact_meta.assoc_str "task" meta_pairs with
   | Some k, Some t -> add (Printf.sprintf "- **Kind**: `%s` (`%s`)" k t)
   | Some k, None -> add (Printf.sprintf "- **Kind**: `%s`" k)
   | None, Some t -> add (Printf.sprintf "- **Task**: `%s`" t)
   | None, None -> ());
  (match Artifact_meta.assoc_str "method" meta_pairs with
   | Some m -> add (Printf.sprintf "- **Method**: `%s`" m)
   | None -> ());
  (match List.assoc_opt "n_obs" meta_pairs with
   | Some v ->
       (match Artifact_meta.json_to_int v with
        | Some n -> add (Printf.sprintf "- **Observations**: `%d`" n)
        | None -> ())
   | None -> ());
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
           match Artifact_meta.json_to_float v with
           | Some f -> Some (Printf.sprintf "%s=%.4g" k f)
           | None -> None
         ) ms
       in
       if parts <> [] then
         add (Printf.sprintf "- **Metrics**: `%s`" (String.concat ", " parts))
   | _ -> ());
  List.rev !lines

let escape_inline_code s =
  let b = Buffer.create (String.length s) in
  String.iter (fun c ->
    match c with
    | '`' -> Buffer.add_char b '\''
    | '\n' | '\r' -> Buffer.add_char b ' '
    | c -> Buffer.add_char b c
  ) s;
  Buffer.contents b

let artifact_hover_markdown ~file_path ~node_name : string option =
  let dir = Filename.dirname file_path in
  let parent = Filename.dirname dir in
  let candidate_dirs =
    if parent = dir then [Filename.concat dir "_pipeline"]
    else [Filename.concat dir "_pipeline"; Filename.concat parent "_pipeline"]
  in
  match List.find_map (fun d -> Artifact_meta.find_node_entry_in_dir ~pipeline_dir:d ~node_name) candidate_dirs with
  | None -> None
  | Some entry ->
      let status = Option.value ~default:"Unknown" (Artifact_meta.assoc_str "status" entry) in
      let runtime = Option.value ~default:"T" (Artifact_meta.assoc_str "runtime" entry) in
      let serializer = Option.value ~default:"default" (Artifact_meta.assoc_str "serializer" entry) in
      let klass = Artifact_meta.assoc_str "class" entry in
      let path = Artifact_meta.assoc_str "path" entry in
      let err_msg = Artifact_meta.assoc_str "error_message" entry in
      let lines = ref [
        Printf.sprintf "**Pipeline Node `%s`**" node_name;
        "";
        Printf.sprintf "- **Status**: `%s` | **Runtime**: `%s` | **Serializer**: `%s`" status runtime serializer;
      ] in
      (match klass with
       | Some c -> lines := !lines @ [Printf.sprintf "- **Class**: `%s`" c]
       | None -> ());
      (match err_msg with
       | Some m -> lines := !lines @ [Printf.sprintf "- **Error**: `%s`" (escape_inline_code m)]
       | None -> ());
      (match path with
       | Some p ->
           (match Artifact_meta.read_meta_assoc_of_artifact p with
            | Some mp -> lines := !lines @ format_meta_lines mp
            | None -> ())
       | None -> ());
      Some (String.concat "\n" !lines)
