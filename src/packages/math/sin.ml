open Ast

(*
--# Sine
--#
--# Compute sine (radians).
--#
--# @name sin
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "sin"
    (make_builtin_named ~name:"sin" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"sin" Float.sin named_args))
    env
