open Ast

(*
--# Standard Deviation
--#
--# Calculates the sample standard deviation of a numeric vector.
--# With `weights`, uses the weighted population denominator (`sum(weights)`).
--#
--# @name sd
--# @param x :: Vector | List The numeric data.
--# @param na_rm :: Bool (Optional) logical. Should missing values be removed? Default is false.
--# @param weights :: Vector[Float] | List[Float] = NA Optional non-negative observation weights.
--# @return :: Float The standard deviation.
--# @example
--#   sd([1, 2, 3, 4, 5])
--#   -- Returns = 1.5811...
--# @family stats
--# @seealso mean, var
--# @export
*)
let register env =
  Env.add "sd"
    (make_builtin_named ~name:"sd" ~variadic:true 1 (fun named_args _env ->
      match Math_common.get_bool_flag "na_rm" false named_args with
      | Error e -> e
      | Ok na_rm ->
      let args = Math_common.positional_args_without ["na_rm"; "weights"] named_args in
      let weight_arg = Math_common.optional_named_arg "weights" named_args in
      match args with
      | [x] ->
          (match weight_arg with
           | Some weight_v ->
               (match Math_utils.extract_numeric_array_with_weights ~label:"sd" ~na_rm x weight_v with
                | Error e -> e
                | Ok (xs, ws) ->
                    if Array.length xs < 2 then Error.value_error "Function `sd` requires at least 2 values."
                    else
                      (match Math_utils.weighted_variance_population xs ws with
                       | Some v -> VFloat (Float.sqrt v)
                       | None -> Error.make_error RuntimeError "Function `sd` internal error: weighted variance could not be computed."))
           | None ->
               (match Math_utils.extract_numeric_array ~label:"sd" ~na_rm x with
                | Error e -> e
                | Ok [||] -> VNA NAFloat
                | Ok nums ->
                    if Array.length nums < 2 then Error.value_error "Function `sd` requires at least 2 values."
                    else
                      (match Math_utils.variance_array nums with
                       | Some v -> VFloat (Float.sqrt v)
                       | None -> VNA NAFloat)))
      | args -> Error.arity_error_named "sd" 1 (List.length args)
    ))
    env
