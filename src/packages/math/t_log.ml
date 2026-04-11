open Ast

(*
--# Natural logarithm
--#
--# Calculates the natural logarithm (base e) of x.
--#
--# @name log
--# @param x :: Number | Vector | NDArray The input value (must be positive).
--# @param na_ignore :: Bool Whether to preserve NA values in inputs. Default is false.
--# @return :: Float | Vector | NDArray The natural logarithm.
--# @example
--#   log(2.71828)
--#   -- Returns = ~1.0
--# @family math
--# @seealso exp
--# @export
*)
let register env =
  Env.add "log"
    (make_builtin_named ~name:"log" ~variadic:true 1 (fun named_args _env ->
      match Math_common.get_bool_flag "na_ignore" false named_args with
      | Error e -> e
      | Ok na_ignore ->
          let args = Math_common.positional_args_without [ "na_ignore" ] named_args in
          match args with
          | [VInt n] ->
              if n <= 0 then Error.value_error "Function `log` is undefined for non-positive numbers."
              else VFloat (Float.log (float_of_int n))
          | [VFloat f] ->
              if f <= 0.0 then Error.value_error "Function `log` is undefined for non-positive numbers."
              else VFloat (Float.log f)
          | [VVector arr] ->
              let result = Array.make (Array.length arr) (VNA NAGeneric) in
              let had_error = ref None in
              Array.iteri (fun i v ->
                if !had_error = None then
                  match v with
                  | VInt n ->
                      if n <= 0 then had_error := Some (Error.value_error "Function `log` is undefined for non-positive numbers.")
                      else result.(i) <- VFloat (Float.log (float_of_int n))
                  | VFloat f ->
                      if f <= 0.0 then had_error := Some (Error.value_error "Function `log` is undefined for non-positive numbers.")
                      else result.(i) <- VFloat (Float.log f)
                  | VNA na_t when na_ignore -> result.(i) <- VNA na_t
                  | VNA _ -> had_error := Some (Error.na_value_error "log")
                  | _ -> had_error := Some (Error.type_error "Function `log` requires numeric values.")
              ) arr;
              (match !had_error with Some e -> e | None -> VVector result)
          | [VNDArray arr] ->
              let result = Array.map (fun f ->
                if f <= 0.0 then nan
                else Float.log f
              ) arr.data in
              if Array.exists Float.is_nan result then
                 Error.value_error "Function `log` encountered non-positive values in NDArray."
              else
                 VNDArray { shape = arr.shape; data = result }
          | [VNA na_t] when na_ignore -> VNA na_t
          | [VNA _] -> Error.na_value_error "log"
          | [_] -> Error.type_error "Function `log` expects a number, numeric Vector, or NDArray."
          | _ -> Error.arity_error_named "log" 1 (List.length args)
    ))
    env
