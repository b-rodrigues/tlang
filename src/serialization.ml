open Ast

let ensure_parent_dir path =
  let dir = Filename.dirname path in
  let rec ensure d =
    if d = "." || d = "/" || Sys.file_exists d then ()
    else (
      ensure (Filename.dirname d);
      Unix.mkdir d 0o755
    )
  in
  ensure dir

let serialize_to_file path value =
  try
    ensure_parent_dir path;
    let oc = open_out_bin path in
    Marshal.to_channel oc value [];
    close_out oc;
    Ok ()
  with exn ->
    Error (Printexc.to_string exn)

let deserialize_from_file path =
  try
    let ic = open_in_bin path in
    let value = (Marshal.from_channel ic : Ast.value) in
    close_in ic;
    Ok value
  with exn ->
    Error (Printexc.to_string exn)

let json_escape s =
  let b = Buffer.create (String.length s + 8) in
  String.iter (function
    | '"' -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n"
    | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t"
    | c -> Buffer.add_char b c
  ) s;
  Buffer.contents b

let json_unescape s =
  let b = Buffer.create (String.length s) in
  let rec loop i =
    if i >= String.length s then ()
    else if s.[i] = '\\' && i + 1 < String.length s then
      let c = s.[i + 1] in
      (match c with
      | '"' -> Buffer.add_char b '"'
      | '\\' -> Buffer.add_char b '\\'
      | 'n' -> Buffer.add_char b '\n'
      | 'r' -> Buffer.add_char b '\r'
      | 't' -> Buffer.add_char b '\t'
      | other -> Buffer.add_char b other);
      loop (i + 2)
    else begin
      Buffer.add_char b s.[i];
      loop (i + 1)
    end
  in
  loop 0;
  Buffer.contents b

let write_registry path entries =
  try
    let oc = open_out path in
    output_string oc "{\n";
    List.iteri (fun i (name, node_path) ->
      Printf.fprintf oc "  \"%s\": \"%s\"%s\n"
        (json_escape name)
        (json_escape node_path)
        (if i = List.length entries - 1 then "" else ",")
    ) entries;
    output_string oc "}\n";
    close_out oc;
    Ok ()
  with exn ->
    Error (Printexc.to_string exn)

let read_registry path =
  try
    if not (Sys.file_exists path) then Error "Registry file not found."
    else
      let ic = open_in path in
      let len = in_channel_length ic in
      let raw = really_input_string ic len in
      close_in ic;
      (* Matches flat JSON object entries of the form:
         "node_name": "artifact_path", with escaped quotes/backslashes supported. *)
      let re =
        Str.regexp
          "\"\\(\\([^\"\\\\]\\|\\\\.\\)+\\)\"[ \n\r\t]*:[ \n\r\t]*\"\\(\\([^\"\\\\]\\|\\\\.\\)*\\)\"" in
      let rec collect pos acc =
        try
          let _ = Str.search_forward re raw pos in
          let name = Str.matched_group 1 raw |> json_unescape in
          let node_path = Str.matched_group 3 raw |> json_unescape in
          collect (Str.match_end ()) ((name, node_path) :: acc)
        with Not_found -> List.rev acc
      in
      Ok (collect 0 [])
  with exn ->
    Error (Printexc.to_string exn)
