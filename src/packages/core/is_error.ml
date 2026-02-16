open Ast

(*
--# Check if a value is an Error
--#
--# Returns true if the value is an Error object, false otherwise.
--#
--# @name is_error
--# @param x :: Any The value to check.
--# @return :: Bool True if x is an Error.
--# @example
--#   is_error(error("Something went wrong"))
--#   -- Returns: true
--# @family core
--# @export
*)
let register env =
  Env.add "is_error"
    (make_builtin ~name:"is_error" 1 (fun args _env ->
      match args with
      | [VError _] -> VBool true
      | [_] -> VBool false
      | _ -> Error.arity_error_named "is_error" ~expected:1 ~received:(List.length args)
    ))
    env
