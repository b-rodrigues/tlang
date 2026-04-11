open Ast

(*
--# Exponential function
--#
--# Calculates e raised to the power of x.
--#
--# @name exp
--# @param x :: Number | Vector | NDArray The input value.
--# @param na_ignore :: Bool Whether to preserve NA values in inputs. Default is false.
--# @return :: Float | Vector | NDArray The exponential.
--# @example
--#   exp(1)
--#   -- Returns = 2.71828...
--# @family math
--# @seealso log, pow
--# @export
*)
let register env =
  Env.add "exp"
    (make_builtin_named ~name:"exp" ~variadic:true 1 (fun named_args _env ->
      let na_ignore = Math_common.named_flag_true "na_ignore" named_args in
      let args = Math_common.positional_args_without [ "na_ignore" ] named_args in
      match args with
      | [VInt n] -> VFloat (Float.exp (float_of_int n))
      | [VFloat f] -> VFloat (Float.exp f)
      | [VVector arr] ->
          let result = Array.make (Array.length arr) (VNA NAGeneric) in
          let had_error = ref None in
          Array.iteri (fun i v ->
            if !had_error = None then
              match v with
              | VInt n -> result.(i) <- VFloat (Float.exp (float_of_int n))
              | VFloat f -> result.(i) <- VFloat (Float.exp f)
              | VNA na_t when na_ignore -> result.(i) <- VNA na_t
              | VNA _ -> had_error := Some (Error.na_value_error "exp")
              | _ -> had_error := Some (Error.type_error "Function `exp` requires numeric values.")
          ) arr;
          (match !had_error with Some e -> e | None -> VVector result)
      | [VNDArray arr] ->
          let result = Array.map Float.exp arr.data in
          VNDArray { shape = arr.shape; data = result }
      | [VNA na_t] when na_ignore -> VNA na_t
      | [VNA _] -> Error.na_value_error "exp"
      | [_] -> Error.type_error "Function `exp` expects a number, numeric Vector, or NDArray."
      | _ -> Error.arity_error_named "exp" 1 (List.length args)
    ))
    env
