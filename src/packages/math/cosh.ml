open Ast

(*
--# Hyperbolic cosine
--#
--# Compute hyperbolic cosine.
--#
--# @name cosh
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "cosh"
    (make_builtin_named ~name:"cosh" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"cosh" Float.cosh named_args))
    env
