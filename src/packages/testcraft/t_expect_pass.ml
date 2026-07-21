open Ast

(*
--# Check whether an Expect value passed
--#
--# Returns `true` if `x` is a `VExpect Expect_pass` value (i.e. an
--# `expect_*` comparison that succeeded). Useful for explicit checks
--# alongside `assert()`.
--#
--# @name expect_pass
--# @param x :: Expect The Expect value to inspect.
--# @return :: Bool True if `x` is a passing Expect value.
--# @example
--#   assert(expect_pass(expect_equal(a, b)))
--# @family testcraft
--# @seealso expect_equal, expect_fail, expect_msg
--# @export
*)
let register env =
  Env.add "expect_pass"
    (make_builtin ~name:"expect_pass" 1 (fun args _env ->
       match args with
       | [ VExpect Expect_pass ] -> VBool true
       | [ VExpect (Expect_stop _ | Expect_hold _) ] -> VBool false
       | [ other ] ->
           Error.type_error
             (Printf.sprintf
                "Function `expect_pass` expects an Expect value, got %s."
                (Utils.type_name other))
       | args -> Error.arity_error_named "expect_pass" 1 (List.length args)))
    env
