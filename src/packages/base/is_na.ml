open Ast

(*
--# Check for NA
--#
--# Checks if a value is NA (Not Available).
--#
--# @name is_na
--# @param x :: Any The value to check.
--# @return :: Bool True if the value is NA.
--# @example
--#   is_na(na())
--#   is_na(1)
--# @family base
--# @seealso na, is_error
--# @export
*)
let register env =
  Env.add "is_na"
    (make_builtin ~name:"is_na" 1 (fun args _env ->
      match args with
      | [VNA _] -> VBool true
      | [_] -> VBool false
      | _ -> Error.arity_error_named "is_na" ~expected:1 ~received:(List.length args)
    ))
    env
