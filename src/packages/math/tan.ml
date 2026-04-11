open Ast

(*
--# Tangent
--#
--# Compute tangent (radians).
--#
--# @name tan
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "tan"
    (make_builtin_named ~name:"tan" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"tan" Float.tan named_args))
    env
