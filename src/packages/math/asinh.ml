open Ast

(*
--# Inverse hyperbolic sine
--#
--# Compute inverse hyperbolic sine.
--#
--# @name asinh
--# @param x :: Number | Vector | NDArray Numeric input.
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
  Env.add "asinh" (make_builtin ~name:"asinh" 1 (fun args _env -> map_numeric_unary ~fname:"asinh" Float.asinh args)) env
