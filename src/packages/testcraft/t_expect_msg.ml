open Ast

(*
--# Get the diagnostic message from a failing Expect value
--#
--# Returns the `Stop`/`Hold` message carried by a failing `VExpect` value.
--# If `x` passed (`Expect_pass`), there is no message to extract and a
--# `VError` is returned instead.
--#
--# @name expect_msg
--# @param x :: Expect The Expect value to inspect.
--# @return :: String The diagnostic message, or an error if `x` is not a failure.
--# @example
--#   expect_msg(expect_equal(1, 2))
--# @family testcraft
--# @seealso expect_equal, expect_pass, expect_fail
--# @export
*)
let register env =
  Env.add "expect_msg"
    (make_builtin ~name:"expect_msg" 1 (fun args _env ->
       match args with
       | [ VExpect (Expect_stop msg | Expect_hold msg) ] -> VString msg
       | [ VExpect Expect_pass ] ->
           Error.value_error "Function `expect_msg` has no message: the Expect value passed."
       | [ other ] ->
           Error.type_error
             (Printf.sprintf
                "Function `expect_msg` expects an Expect value, got %s."
                (Utils.type_name other))
       | args -> Error.arity_error_named "expect_msg" 1 (List.length args)))
    env
