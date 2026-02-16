open Ast

(*
--# Two-argument arctangent
--#
--# Compute `atan2(y, x)` with quadrant-aware angle.
--#
--# @name atan2
--# @param y :: Number Y coordinate.
--# @param x :: Number X coordinate.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "atan2"
    (make_builtin ~name:"atan2" 2 (fun args _env ->
      match args with
      | [VInt y; VInt x] -> VFloat (Float.atan2 (float_of_int y) (float_of_int x))
      | [VInt y; VFloat x] -> VFloat (Float.atan2 (float_of_int y) x)
      | [VFloat y; VInt x] -> VFloat (Float.atan2 y (float_of_int x))
      | [VFloat y; VFloat x] -> VFloat (Float.atan2 y x)
      | [VNA _; _] | [_; VNA _] -> Error.type_error "Function `atan2` encountered NA value. Handle missingness explicitly."
      | [_; _] -> Error.type_error "Function `atan2` expects numeric arguments."
      | _ -> Error.arity_error_named "atan2" ~expected:2 ~received:(List.length args)
    )) env
