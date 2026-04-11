open Ast

(*
--# Truncate values
--#
--# Truncate fractional component toward zero.
--#
--# @name trunc
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "trunc"
    (make_builtin_named ~name:"trunc" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"trunc" Float.trunc named_args))
    env
