open Ast

(*
--# Deserialize Value
--#
--# Deserializes a value from a `.tobj` file.
--#
--# @name deserialize
--# @param path :: String Input file path.
--# @return :: Any
--# @family base
--# @seealso serialize
--# @export
*)
let register env =
  Env.add "deserialize"
    (make_builtin ~name:"deserialize" 1 (fun args _env ->
      match args with
      | [VString path] ->
          (match Serialization.deserialize_from_file path with
          | Ok value -> value
          | Error msg -> Error.make_error FileError (Printf.sprintf "deserialize failed: %s" msg))
      | [_] -> Error.type_error "Function `deserialize` expects a String path."
      | _ -> Error.arity_error_named "deserialize" ~expected:1 ~received:(List.length args)
    ))
    env
