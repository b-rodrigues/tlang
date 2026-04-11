open Ast

(*
--# Power function
--#
--# Calculates base raised to the power of exponent.
--#
--# @name pow
--# @param base :: Number | Vector | NDArray The base.
--# @param exponent :: Number The exponent.
--# @return :: Number | Vector | NDArray The result of base ^ exponent.
--# @example
--#   pow(2, 3)
--#   -- Returns = 8.0
--# @family math
--# @seealso sqrt, exp
--# @export
*)
let register env =
  Env.add "pow"
    (make_builtin_named ~name:"pow" ~variadic:true 2 (fun named_args _env ->
      let na_ignore = Math_common.named_flag_true "na_ignore" named_args in
      let args = Math_common.positional_args_without [ "na_ignore" ] named_args in
      match args with
      | [VInt b; VInt e] -> VFloat (Float.pow (float_of_int b) (float_of_int e))
      | [VFloat b; VInt e] -> VFloat (Float.pow b (float_of_int e))
      | [VInt b; VFloat e] -> VFloat (Float.pow (float_of_int b) e)
      | [VFloat b; VFloat e] -> VFloat (Float.pow b e)
      | [VVector arr; exp_val] ->
          let exp_f = match exp_val with
            | VInt n -> Some (float_of_int n)
            | VFloat f -> Some f
            | _ -> None
          in
          (match exp_f with
           | None -> Error.make_error TypeError "Function `pow` expects a numeric exponent."
           | Some e ->
             let result = Array.make (Array.length arr) (VNA NAGeneric) in
             let had_error = ref None in
             Array.iteri (fun i v ->
               if !had_error = None then
                 match v with
                 | VInt n -> result.(i) <- VFloat (Float.pow (float_of_int n) e)
                 | VFloat f -> result.(i) <- VFloat (Float.pow f e)
                  | VNA na_t when na_ignore -> result.(i) <- VNA na_t
                  | VNA _ -> had_error := Some (Error.na_value_error "pow")
                  | _ -> had_error := Some (Error.make_error TypeError "Function `pow` requires numeric values.")
              ) arr;
              (match !had_error with Some e -> e | None -> VVector result))
      | [VNDArray arr; exp_val] ->
          let exp_f = match exp_val with
            | VInt n -> Some (float_of_int n)
            | VFloat f -> Some f
            | _ -> None
          in
          (match exp_f with
            | None -> Error.make_error TypeError "Function `pow` expects a numeric exponent."
            | Some e ->
              let result = Array.map (fun f -> Float.pow f e) arr.data in
              VNDArray { shape = arr.shape; data = result })
       | [VNA na_t; _] when na_ignore -> VNA na_t
       | [_; VNA na_t] when na_ignore -> VNA na_t
       | [VNA _; _] | [_; VNA _] -> Error.na_value_error "pow"
       | [_; _] -> Error.make_error TypeError "Function `pow` expects numeric arguments (NDArray base supported)."
       | _ -> Error.make_error ArityError "Function `pow` expects 2 arguments."
    ))
    env
