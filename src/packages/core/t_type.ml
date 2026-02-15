open Ast

(*
--# Get the type name of a value
--#
--# Returns a string representation of the value's type (e.g., "Int", "String", "List").
--#
--# @name type
--# @param x :: Any The value to inspect.
--# @return :: String The type name.
--# @example
--#   type(123)
--#   -- Returns: "Int"
--#
--#   type([1, 2])
--#   -- Returns: "List"
--# @family core
--# @export
*)
let register env =
  Env.add "type"
    (make_builtin 1 (fun args _env ->
      match args with
      | [v] -> VString (Utils.type_name v)
      | _ -> Error.arity_error_named "type" ~expected:1 ~received:(List.length args)
    ))
    env
