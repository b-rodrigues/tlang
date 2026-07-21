(*
--# Numeric less-than assertion
--#
--# Passes if `a < b` for numeric arguments (Int or Float). Returns
--# `Expect_hold` when either argument is NA; `Expect_stop` on errors.
--#
--# @name expect_lt
--# @param a :: Int | Float The left-hand numeric value.
--# @param b :: Int | Float The right-hand numeric value.
--# @return :: Expect `Expect_pass` when `a < b`, `Expect_stop` otherwise.
--# @example
--#   assert(expect_lt(1, 2))
--#   assert(expect_lt(1.5, 2.5))
--# @family testcraft
--# @seealso expect_lte, expect_gt, expect_gte, expect_equal
--# @export
*)

(*
--# Numeric less-than-or-equal assertion
--#
--# Passes if `a <= b` for numeric arguments (Int or Float).
--#
--# @name expect_lte
--# @param a :: Int | Float The left-hand numeric value.
--# @param b :: Int | Float The right-hand numeric value.
--# @return :: Expect `Expect_pass` when `a <= b`, `Expect_stop` otherwise.
--# @example
--#   assert(expect_lte(1, 1))
--#   assert(expect_lte(1, 2))
--# @family testcraft
--# @seealso expect_lt, expect_gt, expect_gte, expect_equal
--# @export
*)

(*
--# Numeric greater-than assertion
--#
--# Passes if `a > b` for numeric arguments (Int or Float).
--#
--# @name expect_gt
--# @param a :: Int | Float The left-hand numeric value.
--# @param b :: Int | Float The right-hand numeric value.
--# @return :: Expect `Expect_pass` when `a > b`, `Expect_stop` otherwise.
--# @example
--#   assert(expect_gt(2, 1))
--# @family testcraft
--# @seealso expect_lt, expect_lte, expect_gte, expect_equal
--# @export
*)

(*
--# Numeric greater-than-or-equal assertion
--#
--# Passes if `a >= b` for numeric arguments (Int or Float).
--#
--# @name expect_gte
--# @param a :: Int | Float The left-hand numeric value.
--# @param b :: Int | Float The right-hand numeric value.
--# @return :: Expect `Expect_pass` when `a >= b`, `Expect_stop` otherwise.
--# @example
--#   assert(expect_gte(2, 1))
--#   assert(expect_gte(1, 1))
--# @family testcraft
--# @seealso expect_lt, expect_lte, expect_gt, expect_equal
--# @export
*)

open Ast

let fmt v = "`" ^ Utils.value_to_string v ^ "`"

(* Generic relational comparison for expect_lt/lte/gt/gte.
   Takes separate int and float comparison operators to avoid
   precision loss when comparing large integers via float_of_int. *)
let expect_binop name op_str op_int op_float actual expected =
  match actual, expected with
  | VError err, _ ->
      Expect_stop (Printf.sprintf "`actual` is an error: %s" err.message)
  | _, VError err ->
      Expect_stop (Printf.sprintf "`expected` is an error: %s" err.message)
  | VNA _, _ | _, VNA _ ->
      Expect_hold "One of the arguments is NA."
  | VInt a, VInt b ->
      if op_int a b then Expect_pass
      else Expect_stop (Printf.sprintf "%s %s %s" (fmt actual) op_str (fmt expected))
  | VFloat a, VFloat b ->
      if op_float a b then Expect_pass
      else Expect_stop (Printf.sprintf "%s %s %s" (fmt actual) op_str (fmt expected))
  | VInt a, VFloat b ->
      if op_float (float_of_int a) b then Expect_pass
      else Expect_stop (Printf.sprintf "%s %s %s" (fmt actual) op_str (fmt expected))
  | VFloat a, VInt b ->
      if op_float a (float_of_int b) then Expect_pass
      else Expect_stop (Printf.sprintf "%s %s %s" (fmt actual) op_str (fmt expected))
  | _ ->
      Expect_stop
        (Printf.sprintf "Function `%s` expects numeric arguments, got %s and %s."
           name (Utils.type_name actual) (Utils.type_name expected))

let register env =
  let env =
    Env.add "expect_lt"
      (make_builtin ~name:"expect_lt" 2 (fun args _env ->
         match args with
         | [actual; expected] -> VExpect (expect_binop "expect_lt" "<" (<) (<) actual expected)
         | args -> Error.arity_error_named "expect_lt" 2 (List.length args)))
      env
  in
  let env =
    Env.add "expect_lte"
      (make_builtin ~name:"expect_lte" 2 (fun args _env ->
         match args with
         | [actual; expected] -> VExpect (expect_binop "expect_lte" "<=" (<=) (<=) actual expected)
         | args -> Error.arity_error_named "expect_lte" 2 (List.length args)))
      env
  in
  let env =
    Env.add "expect_gt"
      (make_builtin ~name:"expect_gt" 2 (fun args _env ->
         match args with
         | [actual; expected] -> VExpect (expect_binop "expect_gt" ">" (>) (>) actual expected)
         | args -> Error.arity_error_named "expect_gt" 2 (List.length args)))
      env
  in
  let env =
    Env.add "expect_gte"
      (make_builtin ~name:"expect_gte" 2 (fun args _env ->
         match args with
         | [actual; expected] -> VExpect (expect_binop "expect_gte" ">=" (>=) (>=) actual expected)
         | args -> Error.arity_error_named "expect_gte" 2 (List.length args)))
      env
  in
  env
