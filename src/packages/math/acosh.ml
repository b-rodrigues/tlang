open Ast

(*
--# Inverse hyperbolic cosine
--#
--# Compute inverse hyperbolic cosine.
--#
--# @name acosh
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "acosh"
    (make_builtin_named ~name:"acosh" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"acosh" Float.acosh named_args))
    env
