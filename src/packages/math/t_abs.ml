open Ast

(*
--# Absolute value
--#
--# Returns the absolute value of a number or vector/ndarray elements.
--#
--# @name abs
--# @param x :: Number | Vector | NDArray The input value.
--# @return :: Number | Vector | NDArray The absolute value.
--# @example
--#   abs(-5)
--#   -- Returns: 5
--# @family math
--# @export
*)
let register env =
  Env.add "abs"
    (make_builtin ~name:"abs" 1 (fun args _env ->
      match args with
      | [VInt n] -> VInt (Int.abs n)
      | [VFloat f] -> VFloat (Float.abs f)
      | [VVector arr] ->
          let result = Array.make (Array.length arr) VNull in
          let had_error = ref None in
          Array.iteri (fun i v ->
            if !had_error = None then
              match v with
              | VInt n -> result.(i) <- VInt (Int.abs n)
              | VFloat f -> result.(i) <- VFloat (Float.abs f)
              | VNA _ -> had_error := Some (Error.type_error "Function `abs` encountered NA value. Handle missingness explicitly.")
              | _ -> had_error := Some (Error.type_error "Function `abs` requires numeric values.")
          ) arr;
          (match !had_error with Some e -> e | None -> VVector result)
      | [VNDArray arr] ->
          let result = Array.map (fun f -> Float.abs f) arr.data in
          VNDArray { shape = arr.shape; data = result }
      | [VNA _] -> Error.type_error "Function `abs` encountered NA value. Handle missingness explicitly."
      | [_] -> Error.type_error "Function `abs` expects a number, numeric Vector, or NDArray."
      | _ -> Error.arity_error_named "abs" ~expected:1 ~received:(List.length args)
    ))
    env
