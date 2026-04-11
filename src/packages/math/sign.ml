open Ast

(*
--# Sign of number
--#
--# Return -1, 0, or 1 depending on sign.
--#
--# @name sign
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "sign" (make_builtin_named ~name:"sign" ~variadic:true 1 (fun named_args _env ->
    let sf x = if x > 0.0 then 1.0 else if x < 0.0 then -1.0 else 0.0 in
    Math_common.map_numeric_unary_named ~fname:"sign" sf named_args)) env
