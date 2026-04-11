open Ast

(*
--# Ceiling function
--#
--# Return smallest integer greater than or equal to input.
--#
--# @name ceiling
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "ceiling"
    (make_builtin_named ~name:"ceiling" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"ceiling" Float.ceil named_args))
    env
