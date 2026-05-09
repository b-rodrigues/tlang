open Ast

(*
--# Variance
--#
--# Compute sample variance.
--#
--# @name var
--# @param x :: Vector | List Numeric input.
--# @param na_rm :: Bool = false Remove NA values first.
--# @param weights :: Vector[Float] | List[Float] = NA Optional non-negative observation weights.
--# @return :: Number | Vector Computed result (scalar or vectorized).
--# @family stats
--# @export
*)

let register env =
  Env.add "var" (make_builtin_named ~name:"var" ~variadic:true 1 (fun named_args _ ->
    match Math_common.get_bool_flag "na_rm" false named_args with
    | Error e -> e
    | Ok na_rm ->
    let args = Math_common.positional_args_without ["na_rm"; "weights"] named_args in
    let weight_arg = Math_common.optional_named_arg "weights" named_args in
    match args with
    | [x] ->
        (match weight_arg with
         | Some weight_v ->
             (match Math_utils.extract_numeric_array_with_weights ~label:"var" ~na_rm x weight_v with
              | Error e -> e
              | Ok (xs, ws) ->
                  if Array.length xs < 2 then Error.value_error "Function `var` requires at least 2 values."
                  else
                    (match Math_utils.weighted_variance_population xs ws with
                     | Some v -> VFloat v
                     | None -> Error.make_error RuntimeError "Function `var` internal error: weighted variance could not be computed."))
         | None ->
             (match Math_utils.extract_numeric_array ~label:"var" ~na_rm x with
              | Error e -> e
              | Ok [||] -> VNA NAFloat
              | Ok xs ->
                  let n = Array.length xs in
                  if n < 2 then Error.value_error "Function `var` requires at least 2 values."
                  else
                    (match Math_utils.variance_array xs with
                     | Some v -> VFloat v
                     | None -> VNA NAFloat)))
    | args -> Error.arity_error_named "var" 1 (List.length args))) env
