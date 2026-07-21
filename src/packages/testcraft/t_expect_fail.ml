open Ast

(*
--# Check whether an Expect value failed
--#
--# Returns `true` if `x` is a `VExpect Expect_stop` or `VExpect Expect_hold`
--# value (i.e. an `expect_*` comparison that did not pass). Useful for
--# explicit checks alongside `assert()`.
--#
--# @name expect_fail
--# @param x :: Expect The Expect value to inspect.
--# @return :: Bool True if `x` is a stopping or holding Expect value.
--# @example
--#   assert(expect_fail(expect_equal(1, 2)))
--# @family testcraft
--# @seealso expect_equal, expect_pass, expect_msg
--# @export
*)
let register env =
  Env.add "expect_fail"
    (make_builtin ~name:"expect_fail" 1 (fun args _env ->
       match args with
       | [ VExpect (Expect_stop _ | Expect_hold _) ] -> VBool true
       | [ VExpect Expect_pass ] -> VBool false
       | [ other ] ->
           Error.type_error
             (Printf.sprintf
                "Function `expect_fail` expects an Expect value, got %s."
                (Utils.type_name other))
       | args -> Error.arity_error_named "expect_fail" 1 (List.length args)))
    env
