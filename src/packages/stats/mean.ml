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
--# @param weight :: Vector[Float] | List[Float] = NA Optional non-negative observation weights.
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
      (match Math_common.get_bool_flag "na_rm" false named_args with
      | Error e -> e
      | Ok na_rm ->
      let args = Math_common.positional_args_without ["na_rm"; "weight"] named_args in
      let weight_arg = List.assoc_opt (Some "weight") named_args in
      let extract_nums label vals =
        let rec go acc = function
          | [] -> Ok (List.rev acc)
          | (_, VInt n) :: rest -> go (float_of_int n :: acc) rest
          | (_, VFloat f) :: rest -> go (f :: acc) rest
          | (_, VNA _) :: rest when na_rm -> go acc rest
          | (_, VNA _) :: _ -> Error (Error.na_value_error ~na_rm:true label)
          | _ -> Error (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
        in go [] vals
      in
      let extract_nums_arr_na_rm label arr =
        let nums = ref [] in
        let had_error = ref None in
        for i = 0 to Array.length arr - 1 do
          if !had_error = None then
            match arr.(i) with
            | VInt n -> nums := float_of_int n :: !nums
            | VFloat f -> nums := f :: !nums
            | VNA _ when na_rm -> ()
            | VNA _ -> had_error := Some (Error.na_value_error ~na_rm:true label)
            | _ -> had_error := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
        done;
        match !had_error with Some e -> Error e | None -> Ok (Array.of_list (List.rev !nums))
      in
      let extract_nums_arr label arr =
        let len = Array.length arr in
        let had_error = ref None in
        let result = Array.make len 0.0 in
        for i = 0 to len - 1 do
          if !had_error = None then
            match arr.(i) with
            | VInt n -> result.(i) <- float_of_int n
            | VFloat f -> result.(i) <- f
            | VNA _ -> had_error := Some (Error.na_value_error ~na_rm:true label)
            | _ -> had_error := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
        done;
        match !had_error with Some e -> Error e | None -> Ok result
      in
       let first_arg = match args with a :: _ -> Some a | [] -> None in
       match first_arg with
       | Some (VList []) -> Error.value_error "Function `mean` called on empty List."
       | Some (VList items) ->
           (match weight_arg with
            | Some weight_v ->
                (match Math_utils.extract_numeric_array_with_weights ~label:"mean" ~na_rm (VList items) weight_v with
                 | Error e -> e
                 | Ok (xs, ws) ->
                     (match Math_utils.weighted_mean_array xs ws with
                      | Some m -> VFloat m
                      | None -> Error.value_error "Function `mean` expects `weight` to contain at least one positive value."))
            | None ->
                (match extract_nums "mean" items with
                 | Error e -> e
                 | Ok [] -> VNA NAFloat
                 | Ok nums ->
                   let sum = List.fold_left ( +. ) 0.0 nums in
                   VFloat (sum /. float_of_int (List.length nums))))
       | Some (VVector arr) when Array.length arr = 0 -> Error.value_error "Function `mean` called on empty Vector."
       | Some (VVector arr) ->
           (match weight_arg with
            | Some weight_v ->
                (match Math_utils.extract_numeric_array_with_weights ~label:"mean" ~na_rm (VVector arr) weight_v with
                 | Error e -> e
                 | Ok (xs, ws) ->
                     (match Math_utils.weighted_mean_array xs ws with
                      | Some m -> VFloat m
                      | None -> Error.value_error "Function `mean` expects `weight` to contain at least one positive value."))
            | None ->
                if na_rm then
                  (match extract_nums_arr_na_rm "mean" arr with
                   | Error e -> e
                   | Ok nums when Array.length nums = 0 -> VNA NAFloat
                   | Ok nums ->
                     let sum = Array.fold_left ( +. ) 0.0 nums in
                     VFloat (sum /. float_of_int (Array.length nums)))
                else
                  (match extract_nums_arr "mean" arr with
                   | Error e -> e
                   | Ok nums ->
                     let sum = Array.fold_left ( +. ) 0.0 nums in
                     VFloat (sum /. float_of_int (Array.length nums))))
       | Some (VNA _) -> Error.na_value_error ~na_rm:true "mean"
      | Some _ -> Error.type_error "Function `mean` expects a numeric List or Vector."
      | None -> Error.arity_error_named "mean" 1 (List.length args)
    )))
    env
