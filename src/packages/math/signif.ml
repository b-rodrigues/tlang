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

let map_numeric_unary ~fname f = function
  | [VInt n] -> VFloat (f (float_of_int n))
  | [VFloat x] -> VFloat (f x)
  | [VVector arr] ->
      let out = Array.make (Array.length arr) VNull in
      let err = ref None in
      Array.iteri (fun i v ->
        if !err = None then
          match v with
          | VInt n -> out.(i) <- VFloat (f (float_of_int n))
          | VFloat x -> out.(i) <- VFloat (f x)
          | VNA _ -> err := Some (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." fname))
          | _ -> err := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." fname))
      ) arr;
      (match !err with Some e -> e | None -> VVector out)
  | [VNDArray arr] -> VNDArray { shape = arr.shape; data = Array.map f arr.data }
  | [VNA _] -> Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." fname)
  | [_] -> Error.type_error (Printf.sprintf "Function `%s` expects numeric input." fname)
  | args -> Error.arity_error_named fname ~expected:1 ~received:(List.length args)

let register env =
  Env.add "signif" (make_builtin ~name:"signif" 2 (fun args _env ->
    let signif_f x digits =
      if x = 0.0 then 0.0
      else
        let d = float_of_int digits in
        let scale = Float.pow 10.0 (d -. 1.0 -. Float.floor (Float.log10 (Float.abs x))) in
        Float.round (x *. scale) /. scale
    in
    match args with
    | [x; VInt digits] when digits > 0 -> map_numeric_unary ~fname:"signif" (fun v -> signif_f v digits) [x]
    | [x; VFloat d] when d > 0.0 ->
        let digits = int_of_float d in
        map_numeric_unary ~fname:"signif" (fun v -> signif_f v digits) [x]
    | [_; _] -> Error.value_error "Function `signif` expects positive digits."
    | _ -> Error.arity_error_named "signif" ~expected:2 ~received:(List.length args))) env
