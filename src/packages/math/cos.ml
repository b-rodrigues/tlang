open Ast

(*
--# Cosine
--#
--# Compute cosine (radians).
--#
--# @name cos
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "cos"
    (make_builtin_named ~name:"cos" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"cos" Float.cos named_args))
    env
