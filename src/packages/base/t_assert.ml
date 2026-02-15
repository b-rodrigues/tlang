open Ast

(*
--# Assert Condition
--#
--# Checks if a condition is true, raising an error if false.
--#
--# @name assert
--# @param condition :: Bool The condition to check.
--# @param message :: String (Optional) Custom error message.
--# @return :: Bool True if successful.
--# @example
--#   assert(1 == 1)
--#   assert(x > 0, "x must be positive")
--# @family base
--# @seealso error, is_error
--# @export
*)
let register env =
  Env.add "assert"
    (make_builtin ~variadic:true 1 (fun args _env ->
      match args with
      | [v] ->
          if is_na_value v then
            Error.make_error AssertionError "Assertion received NA."
          else if Utils.is_truthy v then VBool true
          else Error.make_error AssertionError "Assertion failed."
      | [v; VString msg] ->
          if is_na_value v then
            Error.make_error AssertionError ("Assertion received NA: " ^ msg ^ ".")
          else if Utils.is_truthy v then VBool true
          else Error.make_error AssertionError ("Assertion failed: " ^ msg ^ ".")
      | _ -> Error.make_error ArityError (Printf.sprintf "Function `assert` expects 1 or 2 arguments but received %d." (List.length args))
    ))
    env
