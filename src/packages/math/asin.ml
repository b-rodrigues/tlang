open Ast

(*
--# Inverse sine
--#
--# Compute arcsine.
--#
--# @name asin
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "asin"
    (make_builtin_named ~name:"asin" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"asin" Float.asin named_args))
    env
