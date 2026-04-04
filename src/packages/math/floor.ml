open Ast

(*
--# Floor function
--#
--# Return greatest integer less than or equal to input.
--#
--# @name floor
--# @param x :: Number | Vector | NDArray Numeric input.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family math
--# @export
*)

let map_numeric_unary ~fname f = function
  | [VInt n] -> VFloat (f (float_of_int n))
  | [VFloat x] -> VFloat (f x)
  | [VVector arr] ->
      let out = Array.make (Array.length arr) (VNA NAGeneric) in
      let err = ref None in
      Array.iteri (fun i v ->
        if !err = None then
          match v with
          | VInt n -> out.(i) <- VFloat (f (float_of_int n))
          | VFloat x -> out.(i) <- VFloat (f x)
          | VNA _ -> err := Some (Error.na_value_error fname)
          | _ -> err := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." fname))
      ) arr;
      (match !err with Some e -> e | None -> VVector out)
  | [VNDArray arr] -> VNDArray { shape = arr.shape; data = Array.map f arr.data }
  | [VNA _] -> Error.na_value_error fname
  | [_] -> Error.type_error (Printf.sprintf "Function `%s` expects numeric input." fname)
  | args -> Error.arity_error_named fname 1 (List.length args)

let register env =
  Env.add "floor" (make_builtin ~name:"floor" 1 (fun args _env -> map_numeric_unary ~fname:"floor" Float.floor args)) env
