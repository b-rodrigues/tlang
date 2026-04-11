open Ast

(*
--# Absolute value
--#
--# Returns the absolute value of a number or vector/ndarray elements.
--# Raises a TypeError if an NA value is encountered. Use `filter` or explicit
--# missingness handling before calling `abs` on data that may contain NAs.
--#
--# @name abs
--# @param x :: Number | Vector | NDArray The input value.
--# @param na_ignore :: Bool Whether to preserve NA values in inputs. Default is false.
--# @return :: Number | Vector | NDArray The absolute value.
--# @example
--#   abs(-5)
--#   -- Returns = 5
--# @family math
--# @export
*)
let register env =
  Env.add "abs"
    (make_builtin_named ~name:"abs" ~variadic:true 1 (fun named_args _env ->
      match Math_common.get_bool_flag "na_ignore" false named_args with
      | Error e -> e
      | Ok na_ignore ->
          let args = Math_common.positional_args_without [ "na_ignore" ] named_args in
          match args with
          | [VInt n] -> VInt (Int.abs n)
          | [VFloat f] -> VFloat (Float.abs f)
          | [VVector arr] ->
              let result = Array.make (Array.length arr) (VNA NAGeneric) in
              let had_error = ref None in
              Array.iteri (fun i v ->
                if !had_error = None then
                  match v with
                  | VInt n -> result.(i) <- VInt (Int.abs n)
                  | VFloat f -> result.(i) <- VFloat (Float.abs f)
                  | VNA na_t when na_ignore -> result.(i) <- VNA na_t
                  | VNA _ -> had_error := Some (Error.type_error "Function `abs` encountered NA value. Handle missingness explicitly.")
                  | _ -> had_error := Some (Error.type_error "Function `abs` requires numeric values.")
               ) arr;
               (match !had_error with Some e -> e | None -> VVector result)
          | [VNDArray arr] ->
              let result = Array.map (fun f -> Float.abs f) arr.data in
              VNDArray { shape = arr.shape; data = result }
          | [VNA na_t] when na_ignore -> VNA na_t
          | [VNA _] -> Error.type_error "Function `abs` encountered NA value. Handle missingness explicitly."
          | [_] -> Error.type_error "Function `abs` expects a number, numeric Vector, or NDArray."
          | _ -> Error.arity_error_named "abs" 1 (List.length args)
    ))
    env
