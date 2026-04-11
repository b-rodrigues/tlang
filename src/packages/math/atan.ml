open Ast

(*
--# Inverse tangent
--#
--# Compute arctangent.
--#
--# @name atan
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "atan"
    (make_builtin_named ~name:"atan" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"atan" Float.atan named_args))
    env
