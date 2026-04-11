open Ast

(*
--# Inverse cosine
--#
--# Compute arccosine.
--#
--# @name acos
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "acos"
    (make_builtin_named ~name:"acos" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"acos" Float.acos named_args))
    env
