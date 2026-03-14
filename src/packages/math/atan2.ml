open Ast

(*
--# Two-argument arctangent
--#
--# Compute `atan2(y, x)` with quadrant-aware angle.
--#
--# @name atan2
--# @param y :: Number | List | Vector | NDArray Y coordinate(s).
--# @param x :: Number Scalar X coordinate.
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
      let vectorized_result arr x =
        let result = Array.make (Array.length arr) VNull in
        let had_error = ref None in
        Array.iteri (fun i v ->
          if !had_error = None then
            match v with
            | VInt y -> result.(i) <- VFloat (Float.atan2 (float_of_int y) x)
            | VFloat y -> result.(i) <- VFloat (Float.atan2 y x)
            | VNA _ -> had_error := Some (Error.na_value_error "atan2")
            | _ -> had_error := Some (Error.type_error "Function `atan2` requires numeric values."))
          arr;
        match !had_error with Some e -> e | None -> VVector result
      in
      match args with
      | [VInt y; VInt x] -> VFloat (Float.atan2 (float_of_int y) (float_of_int x))
      | [VInt y; VFloat x] -> VFloat (Float.atan2 (float_of_int y) x)
      | [VFloat y; VInt x] -> VFloat (Float.atan2 y (float_of_int x))
      | [VFloat y; VFloat x] -> VFloat (Float.atan2 y x)
      | [VVector arr; x_val] ->
          (match x_val with
           | VNA _ -> Error.na_value_error "atan2"
           | _ ->
                (match scalar_of x_val with
                 | None -> Error.type_error "Function `atan2` expects numeric arguments."
                 | Some x -> vectorized_result arr x))
      | [VList items; x_val] ->
          (match x_val with
           | VNA _ -> Error.na_value_error "atan2"
           | _ ->
               (match scalar_of x_val with
                | None -> Error.type_error "Function `atan2` expects numeric arguments."
                | Some x -> vectorized_result (Array.of_list (List.map snd items)) x))
      | [VNDArray arr; x_val] ->
          (match x_val with
           | VNA _ -> Error.na_value_error "atan2"
           | _ ->
                (match scalar_of x_val with
                | None -> Error.type_error "Function `atan2` expects numeric arguments."
                | Some x ->
                    VNDArray { shape = arr.shape; data = Array.map (fun y -> Float.atan2 y x) arr.data }))
      | [VNA _; _]
      | [VInt _; VNA _]
      | [VFloat _; VNA _] ->
          Error.na_value_error "atan2"
      | [_; _] -> Error.type_error "Function `atan2` expects numeric arguments."
      | _ -> Error.arity_error_named "atan2" 2 (List.length args)
    )) env
