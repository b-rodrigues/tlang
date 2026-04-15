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

let serialized_value_magic = "TLANG_SERIALIZED:"
let serialized_value_format_version = "0.52.0"

(* Derive the prior patchless header (for example, "0.51" from "0.51.0")
   so deserialization can continue to accept artifacts written before patch
   versions were embedded in the serialized value header. Non-zero patch
   releases intentionally return None so patchless-header compatibility stays
   limited to x.y.0 releases. Malformed or otherwise unexpected version
   strings also return None rather than guessing a compatibility header.
   Returns Some(major.minor) for x.y.0 versions, None otherwise. *)
let serialized_value_patchless_compatibility_version =
  match String.split_on_char '.' serialized_value_format_version with
  | [major; minor; "0"] -> Some (major ^ "." ^ minor)
  | _ -> None

let serialized_value_compatible_versions =
  match serialized_value_patchless_compatibility_version with
  | Some legacy -> [serialized_value_format_version; legacy]
  | None -> [serialized_value_format_version]

let serialized_value_header =
  serialized_value_magic ^ serialized_value_format_version ^ "\n"

let read_serialized_value_header ic =
  try
    let magic = really_input_string ic (String.length serialized_value_magic) in
    if magic <> serialized_value_magic then
      Error
        (Printf.sprintf
           "Serialized value is missing the `%s` format header. Rebuild or re-serialize this artifact with the current serializer."
           serialized_value_format_version)
    else
      let version = input_line ic in
      if List.mem version serialized_value_compatible_versions then
        Ok ()
      else
        Error
          (Printf.sprintf
             "Serialized value format version `%s` is not compatible with `%s`. Rebuild or re-serialize this artifact with the current serializer."
             version
             serialized_value_format_version)
  with
  | End_of_file ->
      Error
        (Printf.sprintf
           "Serialized value is truncated or missing the `%s` format header."
           serialized_value_format_version)
  | exn -> Error (Printexc.to_string exn)


(*
--# JSON String Escaper
--#
--# Escapes special characters for JSON compatibility.
--#
--# @name json_escape
--# @param s :: String The string to escape.
--# @return :: String The escaped string.
--# @private
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
--# @private
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
--# @private
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
--# @private
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

let json_date_string days =
  let year, month, day = Chrono.civil_from_days days in
  Printf.sprintf "%04d-%02d-%02d" year month day

let json_datetime_string micros tz =
  let year, month, day, hour, minute, second, micros_part =
    Chrono.split_datetime_micros micros
  in
  let base =
    Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d"
      year month day hour minute second
  in
  let frac =
    if micros_part = 0 then ""
    else Printf.sprintf ".%06d" micros_part
  in
  let tz_suffix =
    match tz with
    | Some name when name <> "" -> "Z[" ^ name ^ "]"
    | _ -> "Z"
  in
  base ^ frac ^ tz_suffix

let rec value_to_yojson (v : Ast.value) : Yojson.Safe.t =
  match v with
  | VInt i -> `Int i
  | VFloat f -> `Float f
  | VBool b -> `Bool b
  | VString s -> `String s
  | VRawCode s -> `String s
  | VDate days -> `String (json_date_string days)
  | VDatetime (micros, tz) -> `String (json_datetime_string micros tz)
  | VNA _ -> `Null
  | VList items -> `List (List.map (fun (_, v) -> value_to_yojson v) items)
  | VDict pairs -> `Assoc (List.map (fun (k, v) -> (k, value_to_yojson v)) pairs)
  | VVector arr -> `List (Array.to_list arr |> List.map value_to_yojson)
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
  | VError err ->
      `Assoc [
        ("type", `String "VError");
        ("code", `String (Ast.Utils.error_code_to_string err.code));
        ("message", `String err.message);
        ("na_count", `Int err.na_count);
        ("context", `Assoc (List.map (fun (k, v) -> (k, value_to_yojson v)) err.context));
        ("location", (match err.location with
           | Some loc -> `Assoc [
               ("file", match loc.file with Some f -> `String f | None -> `Null);
               ("line", `Int loc.line);
               ("column", `Int loc.column)
             ]
           | None -> `Null))
      ]
  | VShellResult { sr_stdout; _ } ->
      (* Serialize shell result as its stdout string *)
      `String sr_stdout
  | VPeriod p ->
      `Assoc [
        ("years", `Int p.p_years);
        ("months", `Int p.p_months);
        ("days", `Int p.p_days);
        ("hours", `Int p.p_hours);
        ("minutes", `Int p.p_minutes);
        ("seconds", `Int p.p_seconds);
        ("micros", `Int p.p_micros);
      ]
  | VDuration seconds ->
      `Float seconds
  | VInterval iv ->
      `Assoc [
        ("start", `String (json_datetime_string iv.iv_start iv.iv_tz));
        ("end", `String (json_datetime_string iv.iv_end iv.iv_tz));
        ("timezone",
         (match iv.iv_tz with
          | Some tz -> `String tz
          | None -> `Null));
      ]
  | VFactor _ | VSerializer _ ->
      invalid_arg "value_to_yojson: VFactor/VSerializer is not supported for JSON serialization"
  | VUnquote _ | VUnquoteSplice _ | VDynamicArg _ | VQuo _ | VEnv _ ->
      invalid_arg "value_to_yojson: metaprogramming intermediate values are not serializable"
  | VLens l ->
      let rec lens_to_yojson = function
        | Ast.ColLens s -> `Assoc [("type", `String "ColLens"); ("name", `String s)]
        | Ast.IdxLens i -> `Assoc [("type", `String "IdxLens"); ("index", `Int i)]
        | Ast.RowLens i -> `Assoc [("type", `String "RowLens"); ("index", `Int i)]
        | Ast.NodeLens n -> `Assoc [("type", `String "NodeLens"); ("name", `String n)]
        | Ast.NodeMetaLens (n, f) -> `Assoc [("type", `String "NodeMetaLens"); ("name", `String n); ("field", `String f)]
        | Ast.EnvVarLens (n, v) -> `Assoc [("type", `String "EnvVarLens"); ("node", `String n); ("var", `String v)]
        | Ast.CompositeLens (l1, l2) -> `Assoc [("type", `String "CompositeLens"); ("left", lens_to_yojson l1); ("right", lens_to_yojson l2)]
        | Ast.FilterLens p -> `Assoc [("type", `String "FilterLens"); ("predicate", value_to_yojson p)]
      in
      `Assoc [("class", `String "VLens"); ("data", lens_to_yojson l)]
  | VNodeResult { v; _ } -> value_to_yojson v

let rec yojson_to_value (j : Yojson.Safe.t) : Ast.value =
  match j with
  | `Int i -> VInt i
  | `Float f -> VFloat f
  | `Bool b -> VBool b
  | `String s -> VString s
  | `Null -> (VNA NAGeneric)
  | `List l -> VList (List.map (fun x -> (None, yojson_to_value x)) l)
  | `Assoc a ->
      (match List.assoc_opt "class" a with
       | Some (`String "VLens") ->
           (match List.assoc_opt "data" a with
            | Some (`Assoc d) ->
                let rec yojson_to_lens = function
                  | `Assoc items ->
                      (match List.assoc_opt "type" items with
                       | Some (`String "ColLens") -> Ast.ColLens (match List.assoc "name" items with `String s -> s | _ -> "")
                       | Some (`String "IdxLens") -> Ast.IdxLens (match List.assoc "index" items with `Int i -> i | _ -> 0)
                       | Some (`String "RowLens") -> Ast.RowLens (match List.assoc "index" items with `Int i -> i | _ -> 0)
                       | Some (`String "NodeLens") -> Ast.NodeLens (match List.assoc "name" items with `String s -> s | _ -> "")
                       | Some (`String "NodeMetaLens") ->
                            let node = match List.assoc "name" items with `String s -> s | _ -> "" in
                            let field = match List.assoc "field" items with `String s -> s | _ -> "" in
                            Ast.NodeMetaLens (node, field)
                       | Some (`String "EnvVarLens") ->
                            let node = match List.assoc "node" items with `String s -> s | _ -> "" in
                            let var = match List.assoc "var" items with `String s -> s | _ -> "" in
                            Ast.EnvVarLens (node, var)
                       | Some (`String "CompositeLens") ->
                           Ast.CompositeLens (yojson_to_lens (List.assoc "left" items),
                                              yojson_to_lens (List.assoc "right" items))
                       | Some (`String "FilterLens") ->
                           Ast.FilterLens (yojson_to_value (List.assoc "predicate" items))
                       | _ -> Ast.ColLens "error")
                  | _ -> Ast.ColLens "error"
                in
                VLens (yojson_to_lens (`Assoc d))
            | _ -> VDict (List.map (fun (k, v) -> (k, yojson_to_value v)) a))
       | _ -> VDict (List.map (fun (k, v) -> (k, yojson_to_value v)) a))
  | _ ->
      invalid_arg ("yojson_to_value: unsupported Yojson constructor: " ^ Yojson.Safe.to_string j)

let yojson_to_verror (j : Yojson.Safe.t) : Ast.value =
  match j with
  | `Assoc a ->
      (match List.assoc_opt "type" a with
       | Some (`String "VError") ->
           let code = match List.assoc_opt "code" a with
             | Some (`String s) -> Ast.Utils.error_code_of_string s
             | _ -> Ast.RuntimeError
           in
           let message = match List.assoc_opt "message" a with
             | Some (`String s) -> s
             | _ -> "Unknown error"
           in
           let na_count = match List.assoc_opt "na_count" a with
             | Some (`Int i) -> i
             | _ -> 0
           in
           let context = match List.assoc_opt "context" a with
             | Some (`Assoc ctx) -> List.map (fun (k, v) -> (k, yojson_to_value v)) ctx
             | _ -> []
           in
           let location = match List.assoc_opt "location" a with
              | Some (`Assoc loc) ->
                  Some ({
                    file = (match List.assoc_opt "file" loc with Some (`String f) -> Some f | _ -> None);
                    line = (match List.assoc_opt "line" loc with Some (`Int i) -> i | _ -> 0);
                    column = (match List.assoc_opt "column" loc with Some (`Int i) -> i | _ -> 0);
                  } : Ast.source_location)
             | _ -> None
            in
            Ast.VError { code; message; context; location; na_count }
       | _ ->
           invalid_arg
             ("yojson_to_verror: expected object with type=\"VError\", got: "
              ^ Yojson.Safe.to_string j))
  | _ ->
      invalid_arg ("yojson_to_verror: unsupported Yojson constructor: " ^ Yojson.Safe.to_string j)

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

let read_verror_json path =
  try
    if not (Sys.file_exists path) then Error "File not found"
    else
      let j = Yojson.Safe.from_file path in
      Ok (yojson_to_verror j)
  with exn -> Error (Printexc.to_string exn)

(*
--# Binary Serialization
--#
--# Serializes any T value to a file using OCaml's Marshal module.
--# Includes a content digest for integrity verification on deserialization.
--#
--# @name serialize_to_file
--# @param path :: String Destination file path.
--# @param value :: Any The T value to serialize.
--# @return :: Result[Null, String] Ok or error.
--# @private
--# *)
let serialize_to_file path value =
  try
    ensure_parent_dir path;
    let payload = Marshal.to_bytes value [] in
    let digest = Digest.bytes payload in
    let hex = Digest.to_hex digest in
    let oc = open_out_bin path in
    output_string oc serialized_value_header;
    output_string oc hex;
    output_char oc '\n';
    output_bytes oc payload;
    close_out oc;
    Ok ()
  with exn ->
    Error (Printexc.to_string exn)

(*
--# Binary Deserialization
--#
--# Reads a serialized T value from a file. Verifies an integrity digest
--# before unmarshalling to reject tampered or externally-supplied artifacts.
--#
--# SECURITY NOTE: OCaml Marshal is not safe for fully untrusted input.
--# The MD5 digest check detects accidental corruption only — MD5 is not
--# cryptographically secure and provides no protection against intentional
--# tampering. Only load .tobj files produced by your own T installation.
--#
--# @name deserialize_from_file
--# @param path :: String Source file path.
--# @return :: Result[Any, String] Value or error.
--# @private
--# *)
let deserialize_from_file path =
  try
    let ic = open_in_bin path in
    let result =
      match read_serialized_value_header ic with
      | Error original_err ->
          (* Fallback: is it a JSON-serialized VError?
             We check for a 'class' file in the same directory. *)
          let class_path = Filename.concat (Filename.dirname path) "class" in
          if Sys.file_exists class_path then
            (close_in ic;
             let ic2 = open_in class_path in
             let cls = input_line ic2 |> String.trim in
             close_in ic2;
             if cls = "VError" then
               read_verror_json path
             else
               (* Fallback: try reading as JSON if the class is one of the basic T types
                  or just try read_json as a general fallback for text-based artifacts. *)
               read_json path)
          else
            (close_in ic; Error original_err)
      | Ok () ->
          (* Remember position right after the version header so we can fall
             back to legacy (digest-less) deserialization if needed. *)
          let pos_after_header = pos_in ic in
          (* Try to read the hex digest line *)
          (match (try Some (input_line ic) with End_of_file -> None) with
           | None ->
               Error "Serialized value is truncated: no data after the format header."
           | Some hex_line ->
               let hex = String.trim hex_line in
               (* Validate hex digest format: 32 hex chars for MD5 (OCaml Digest module).
                  If the digest algorithm changes, update this length accordingly. *)
               let valid_hex =
                 String.length hex = 32 &&
                 String.for_all (fun c ->
                   (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
                 ) hex
               in
               if valid_hex then
                 (* New format: verify digest then unmarshal *)
                 let pos = pos_in ic in
                 let total = in_channel_length ic in
                 let remaining = total - pos in
                 if remaining <= 0 then
                   Error "Serialized value has no payload after the integrity digest."
                 else
                   let payload = Bytes.create remaining in
                   really_input ic payload 0 remaining;
                   let actual_digest = Digest.bytes payload in
                   let actual_hex = Digest.to_hex actual_digest in
                   if String.lowercase_ascii actual_hex <> String.lowercase_ascii hex then
                     Error "Integrity check failed: the serialized value has been modified or corrupted. Re-serialize this artifact with the current version of T."
                   else
                     let value = (Marshal.from_bytes payload 0 : Ast.value) in
                     Ok value
               else begin
                 (* Legacy format (no digest): seek back to right after the
                    version header and unmarshal directly. Emit a warning so
                    the user knows to re-serialize. *)
                 Printf.eprintf
                   "Warning: %s was serialized without an integrity digest (legacy format). Re-serialize this artifact with the current version of T for full integrity checking.\n%!"
                   path;
                 seek_in ic pos_after_header;
                 let value = (Marshal.from_channel ic : Ast.value) in
                 Ok value
               end)
    in
    let _ = close_in_noerr ic in
    result
  with exn ->
    Error (Printexc.to_string exn)
