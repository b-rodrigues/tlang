open Ast

(*
--# Floor function
--#
--# Return greatest integer less than or equal to input.
--#
--# @name floor
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "floor"
    (make_builtin_named ~name:"floor" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"floor" Float.floor named_args))
    env
