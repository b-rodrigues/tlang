open Ast

(*
--# Ceiling alias
--#
--# Alias for `ceiling`.
--#
--# @name ceil
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "ceil"
    (make_builtin_named ~name:"ceil" ~variadic:true 1 (fun named_args _env ->
      Math_common.map_numeric_unary_named ~fname:"ceil" Float.ceil named_args))
    env
