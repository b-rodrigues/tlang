open Ast

(*
--# Hyperbolic sine
--#
--# Compute hyperbolic sine.
--#
--# @name sinh
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "sinh"
    (make_builtin_named ~name:"sinh" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"sinh" Float.sinh named_args))
    env
