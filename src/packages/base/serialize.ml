open Ast

(*
--# Serialize Value
--#
--# Serializes a value to a `.tobj` file.
--#
--# @name serialize
--# @param value :: Any Value to serialize.
--# @param path :: String Output file path.
--# @return :: Null
--# @family base
--# @seealso deserialize
--# @export
*)
let register env =
  Env.add "serialize"
    (make_builtin ~name:"serialize" 2 (fun args _env ->
      match args with
      | [value; VString path] ->
          (match Serialization.serialize_to_file path value with
          | Ok () -> VNull
          | Error msg -> Error.make_error FileError (Printf.sprintf "serialize failed: %s" msg))
      | [_; _] -> Error.type_error "Function `serialize` expects (Any, String)."
      | _ -> Error.arity_error_named "serialize" ~expected:2 ~received:(List.length args)
    ))
    env
