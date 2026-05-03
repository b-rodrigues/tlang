open Ast

let register env =
  let env =
    (*
    --# Write Value to JSON
    --#
    --# Serializes a T value to a JSON file. This is used as the universal
    --# baseline for object transport between runtimes in the sandbox interchange protocol.
    --#
    --# @name t_write_json
    --# @param value :: Any The value to serialize.
    --# @param path :: String Path to the destination file.
    --# @return :: NA
    --# @family json
    --# @export
    *)
    Env.add "t_write_json"
      (make_builtin ~name:"t_write_json" 2 (fun args _env ->
        match args with
        | [value; VString path] ->
            (match Serialization.write_json path value with
            | Ok () -> (VNA NAGeneric)
            | Error msg -> Error.make_error FileError (Printf.sprintf "t_write_json failed: %s" msg))
        | [_; _] -> Error.type_error "Function `t_write_json` expects (Any, String)."
        | _ -> Error.arity_error_named "t_write_json" 2 (List.length args)
      ))
      env
  in
  (*
  --# Read Value from JSON
  --#
  --# Deserializes a T value from a JSON file. Automatically handles type
  --# conversion for scalars, lists, and dictionaries.
  --#
  --# @name t_read_json
  --# @param path :: String Path to the JSON file.
  --# @return :: Any The deserialized value.
  --# @family json
  --# @export
  *)
  Env.add "t_read_json"
    (make_builtin ~name:"t_read_json" 1 (fun args _env ->
      match args with
      | [VString path] ->
          (match Serialization.read_json path with
          | Ok value -> value
          | Error msg -> Error.make_error FileError (Printf.sprintf "t_read_json failed: %s" msg))
      | [_] -> Error.type_error "Function `t_read_json` expects a String path."
      | _ -> Error.arity_error_named "t_read_json" 1 (List.length args)
    ))
    env
