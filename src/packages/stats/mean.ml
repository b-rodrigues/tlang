open Ast

(*
--# Compute arithmetic mean of numeric values
--#
--# The mean is the sum of values divided by the count. This function
--# handles NA values explicitly through the na_rm parameter.
--#
--# @name mean
--# @param x :: Vector[Float] | List[Float] Input numeric data. Must contain at least one value.
--# @param na_rm :: Bool = false Remove NA values before computation.
--# @param weights :: Vector[Float] | List[Float] = NA Optional non-negative observation weights.
--# @return :: Float | NA The arithmetic mean, or NA if input contains NA and na_rm is false
--# @example
--#   mean([1, 2, 3])
--#   -- Returns = 2.0
--#
--#   mean([1, NA, 3], na_rm = true)
--#   -- Returns = 2.0
--#
--# @seealso median, sd, sum
--# @family descriptive-statistics
--# @intent
--#   purpose = "Compute central tendency of numeric data"
--#   use_when = "Summarizing distributions or comparing groups"
--#   alternatives = "Use median() for robust center; sd() for spread"
--# @export
*)
let register env =
  Env.add "mean"
    (make_builtin_named ~name:"mean" ~variadic:true 1 (fun named_args _env ->
      match Math_common.get_bool_flag "na_rm" false named_args with
      | Error e -> e
      | Ok na_rm ->
      let args = Math_common.positional_args_without ["na_rm"; "weights"] named_args in
      let weight_arg = Math_common.optional_named_arg "weights" named_args in
      match args with
      | [VVector [||]] | [VList []] -> Error.value_error "Function `mean` called on empty List."
      | [x] ->
           (match weight_arg with
            | Some weight_v ->
                (match Math_utils.extract_numeric_array_with_weights ~label:"mean" ~na_rm x weight_v with
                 | Error e -> e
                 | Ok (xs, ws) ->
                     (match Math_utils.weighted_mean_array xs ws with
                      | Some m -> VFloat m
                      | None -> Error.value_error "Function `mean` expects `weights` to contain at least one positive value."))
            | None ->
                (match Math_utils.extract_numeric_array ~label:"mean" ~na_rm x with
                 | Error e -> e
                 | Ok nums ->
                     (match Math_utils.mean_array nums with
                      | Some m -> VFloat m
                      | None -> VNA NAFloat)))
      | args -> Error.arity_error_named "mean" 1 (List.length args)
    )) env
