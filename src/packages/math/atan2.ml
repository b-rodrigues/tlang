open Ast

(*
--# Two-argument arctangent
--#
--# Compute `atan2(y, x)` with quadrant-aware angle.
--#
--# @name atan2
--# @param y :: Number | Vector | NDArray Y coordinate(s).
--# @param x :: Number X coordinate.
--# @return :: Number | Vector | NDArray Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let register env =
  Env.add "atan2"
    (make_builtin ~name:"atan2" 2 (fun args _env ->
      let scalar_of = function
        | VInt n -> Some (float_of_int n)
        | VFloat f -> Some f
        | _ -> None
      in
      match args with
      | [VInt y; VInt x] -> VFloat (Float.atan2 (float_of_int y) (float_of_int x))
      | [VInt y; VFloat x] -> VFloat (Float.atan2 (float_of_int y) x)
      | [VFloat y; VInt x] -> VFloat (Float.atan2 y (float_of_int x))
      | [VFloat y; VFloat x] -> VFloat (Float.atan2 y x)
      | [VVector arr; x_val] ->
          (match scalar_of x_val with
           | None -> Error.type_error "Function `atan2` expects numeric arguments."
           | Some x ->
               let result = Array.make (Array.length arr) VNull in
               let had_error = ref None in
               Array.iteri (fun i v ->
                 if !had_error = None then
                   match v with
                   | VInt y -> result.(i) <- VFloat (Float.atan2 (float_of_int y) x)
                   | VFloat y -> result.(i) <- VFloat (Float.atan2 y x)
                   | VNA _ -> had_error := Some (Error.type_error "Function `atan2` encountered NA value. Handle missingness explicitly.")
                   | _ -> had_error := Some (Error.type_error "Function `atan2` requires numeric values."))
                 arr;
               match !had_error with Some e -> e | None -> VVector result)
      | [VNDArray arr; x_val] ->
          (match scalar_of x_val with
           | None -> Error.type_error "Function `atan2` expects numeric arguments."
           | Some x ->
               VNDArray { shape = arr.shape; data = Array.map (fun y -> Float.atan2 y x) arr.data })
      | [VNA _; _] | [_; VNA _] -> Error.type_error "Function `atan2` encountered NA value. Handle missingness explicitly."
      | [_; _] -> Error.type_error "Function `atan2` expects numeric arguments."
      | _ -> Error.arity_error_named "atan2" 2 (List.length args)
    )) env
