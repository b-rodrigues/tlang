open Ast

(*
--# Hyperbolic tangent
--#
--# Compute hyperbolic tangent.
--#
--# @name tanh
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "tanh"
    (make_builtin_named ~name:"tanh" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"tanh" Float.tanh named_args))
    env
