open Ast

(*
--# Inverse hyperbolic sine
--#
--# Compute inverse hyperbolic sine.
--#
--# @name asinh
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "asinh"
    (make_builtin_named ~name:"asinh" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"asinh" Float.asinh named_args))
    env
