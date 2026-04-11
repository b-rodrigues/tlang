open Ast

(*
--# Inverse hyperbolic tangent
--#
--# Compute inverse hyperbolic tangent.
--#
--# @name atanh
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "atanh"
    (make_builtin_named ~name:"atanh" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"atanh" Float.atanh named_args))
    env
