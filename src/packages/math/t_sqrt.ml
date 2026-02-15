open Ast

(*
--# Square root
--#
--# Calculates the square root of x.
--#
--# @name sqrt
--# @param x :: Number | Vector | NDArray The input value (must be non-negative).
--# @return :: Float | Vector | NDArray The square root.
--# @example
--#   sqrt(16)
--#   -- Returns: 4.0
--# @family math
--# @seealso pow
--# @export
*)
let register env =
  Env.add "sqrt"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VInt n] ->
          if n < 0 then Error.value_error "Function `sqrt` is undefined for negative numbers."
          else VFloat (Float.sqrt (float_of_int n))
      | [VFloat f] ->
          if f < 0.0 then Error.value_error "Function `sqrt` is undefined for negative numbers."
          else VFloat (Float.sqrt f)
      | [VVector arr] ->
          let result = Array.make (Array.length arr) VNull in
          let had_error = ref None in
          Array.iteri (fun i v ->
            if !had_error = None then
              match v with
              | VInt n ->
                  if n < 0 then had_error := Some (Error.value_error "Function `sqrt` is undefined for negative numbers.")
                  else result.(i) <- VFloat (Float.sqrt (float_of_int n))
              | VFloat f ->
                  if f < 0.0 then had_error := Some (Error.value_error "Function `sqrt` is undefined for negative numbers.")
                  else result.(i) <- VFloat (Float.sqrt f)
              | VNA _ -> had_error := Some (Error.type_error "Function `sqrt` encountered NA value. Handle missingness explicitly.")
              | _ -> had_error := Some (Error.type_error "Function `sqrt` requires numeric values.")
          ) arr;
          (match !had_error with Some e -> e | None -> VVector result)
      | [VNDArray arr] ->
          let result = Array.map (fun f ->
            if f < 0.0 then nan (* Use NaN for negative sqrt in NDArray to match typical vectorized behavior, or error? *)
            else Float.sqrt f
          ) arr.data in
          if Array.exists Float.is_nan result then
             Error.value_error "Function `sqrt` encountered negative values in NDArray."
          else
             VNDArray { shape = arr.shape; data = result }
      | [VNA _] -> Error.type_error "Function `sqrt` encountered NA value. Handle missingness explicitly."
      | [_] -> Error.type_error "Function `sqrt` expects a number, numeric Vector, or NDArray."
      | _ -> Error.arity_error_named "sqrt" ~expected:1 ~received:(List.length args)
    ))
    env
