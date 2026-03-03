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

(*
--# Binary Serialization
--#
--# Serializes any T value to a file using OCaml's Marshal module.
--#
--# @name serialize_to_file
--# @param path :: String Destination file path.
--# @param value :: Any The T value to serialize.
--# @return :: Result[Null, String] Ok or error.
*)
let serialize_to_file path value =
  try
    ensure_parent_dir path;
    let oc = open_out_bin path in
    Marshal.to_channel oc value [];
    close_out oc;
    Ok ()
  with exn ->
    Error (Printexc.to_string exn)

(*
--# Binary Deserialization
--#
--# Reads a serialized T value from a file.
--#
--# @name deserialize_from_file
--# @param path :: String Source file path.
--# @return :: Result[Any, String] Value or error.
*)
let deserialize_from_file path =
  try
    let ic = open_in_bin path in
    let value = (Marshal.from_channel ic : Ast.value) in
    close_in ic;
    Ok value
  with exn ->
    Error (Printexc.to_string exn)

(*
--# JSON String Escaper
--#
--# Escapes special characters for JSON compatibility.
--#
--# @name json_escape
--# @param s :: String The string to escape.
--# @return :: String The escaped string.
*)
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

(*
--# JSON String Unescaper
--#
--# Decodes escaped characters from a JSON string.
--#
--# @name json_unescape
--# @param s :: String The escaped string.
--# @return :: String The literal string.
*)
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

(*
--# Registry Maintenance (Writer)
--#
--# Writes a flat JSON object mapping node names to artifact paths.
--#
--# @name write_registry
--# @param path :: String Destination file.
--# @param entries :: List[(String, String)] Name-path pairs.
--# @return :: Result[Null, String] Status.
*)
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

(*
--# Registry Maintenance (Reader)
--#
--# Parses a registry JSON file back into a list of name-path pairs.
--#
--# @name read_registry
--# @param path :: String Source file.
--# @return :: Result[List[(String, String)], String] Entries or error.
*)
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

let json_list items =
  "[" ^ (String.concat ", " (List.map (fun s -> "\"" ^ json_escape s ^ "\"") items)) ^ "]"

let json_dict pairs =
  "{\n" ^
  (String.concat ",\n" (List.map (fun (k, v) ->
    Printf.sprintf "  \"%s\": %s" (json_escape k) v
  ) pairs)) ^
  "\n}"

let rec value_to_yojson (v : Ast.value) : Yojson.Safe.t =
  match v with
  | VInt i -> `Int i
  | VFloat f -> `Float f
  | VBool b -> `Bool b
  | VString s -> `String s
  | VNull -> `Null
  | VList items -> `List (List.map (fun (_, v) -> value_to_yojson v) items)
  | VDict pairs -> `Assoc (List.map (fun (k, v) -> (k, value_to_yojson v)) pairs)
  | VVector arr -> `List (Array.to_list arr |> List.map value_to_yojson)
  | VNA _ -> `Null
  | VSymbol _ as sym -> `String (Ast.Utils.value_to_string sym)
  | VDataFrame _ ->
      invalid_arg "value_to_yojson: VDataFrame is not supported for JSON serialization"
  | VPipeline _ ->
      invalid_arg "value_to_yojson: VPipeline is not supported for JSON serialization"
  | VLambda _ ->
      invalid_arg "value_to_yojson: VLambda is not supported for JSON serialization"
  | VBuiltin _ ->
      invalid_arg "value_to_yojson: VBuiltin is not supported for JSON serialization"
  | VFormula _ ->
      invalid_arg "value_to_yojson: VFormula is not supported for JSON serialization"
  | VNDArray _ ->
      invalid_arg "value_to_yojson: VNDArray is not supported for JSON serialization"
  | VIntent _ ->
      invalid_arg "value_to_yojson: VIntent is not supported for JSON serialization"
  | VNode _ ->
      invalid_arg "value_to_yojson: VNode is not supported for JSON serialization"
  | VExpr _ ->
      invalid_arg "value_to_yojson: VExpr is not supported for JSON serialization"
  | VComputedNode _ ->
      invalid_arg "value_to_yojson: VComputedNode is not supported for JSON serialization"
  | VError _ ->
      invalid_arg "value_to_yojson: VError is not supported for JSON serialization"
  | VShellResult { sr_stdout; _ } ->
      (* Serialize shell result as its stdout string *)
      `String sr_stdout

let rec yojson_to_value (j : Yojson.Safe.t) : Ast.value =
  match j with
  | `Int i -> VInt i
  | `Float f -> VFloat f
  | `Bool b -> VBool b
  | `String s -> VString s
  | `Null -> VNull
  | `List l -> VList (List.map (fun x -> (None, yojson_to_value x)) l)
  | `Assoc a -> VDict (List.map (fun (k, v) -> (k, yojson_to_value v)) a)
  | _ ->
      invalid_arg ("yojson_to_value: unsupported Yojson constructor: " ^ Yojson.Safe.to_string j)

let write_json path value =
  try
    ensure_parent_dir path;
    let j = value_to_yojson value in
    Yojson.Safe.to_file path j;
    Ok ()
  with exn -> Error (Printexc.to_string exn)

let read_json path =
  try
    if not (Sys.file_exists path) then Error "File not found"
    else
      let j = Yojson.Safe.from_file path in
      Ok (yojson_to_value j)
  with exn -> Error (Printexc.to_string exn)
