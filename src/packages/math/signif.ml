open Ast

(*
--# Significant-digit rounding
--#
--# Round to a fixed number of significant digits.
--#
--# @name signif
--# @param x :: Number | Vector | NDArray Numeric input.
--# @param digits :: Int Number of significant digits (> 0).
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "signif" (make_builtin_named ~name:"signif" ~variadic:true 2 (fun named_args _env ->
    let signif_f x digits =
      if x = 0.0 then 0.0
      else
        let d = float_of_int digits in
        let scale = Float.pow 10.0 (d -. 1.0 -. Float.floor (Float.log10 (Float.abs x))) in
        Float.round (x *. scale) /. scale
    in
    let na_ignore = Math_common.named_flag_true "na_ignore" named_args in
    let args = Math_common.positional_args_without [ "na_ignore" ] named_args in
    match args with
    | [x; VInt digits] when digits > 0 ->
        Math_common.map_numeric_unary ~fname:"signif" ~na_ignore (fun v -> signif_f v digits) [x]
    | [_; VInt _] -> Error.value_error "Function `signif` expects positive integer digits."
    | [x; VFloat d] when d > 0.0 ->
        let digits = int_of_float d in
        if float_of_int digits = d && digits > 0 then
          Math_common.map_numeric_unary ~fname:"signif" ~na_ignore (fun v -> signif_f v digits) [x]
        else
          Error.value_error "Function `signif` expects positive integer digits."
    | [_; _] -> Error.value_error "Function `signif` expects positive integer digits."
    | _ -> Error.arity_error_named "signif" 2 (List.length args))) env
