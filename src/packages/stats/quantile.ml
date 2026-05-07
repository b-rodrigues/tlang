open Ast

(*
--# Quantiles
--#
--# Computes the quantile of a distribution at a specified probability.
--#
--# @name quantile
--# @param x :: Vector | List The numeric data.
--# @param probs :: Float The probability (0 to 1).
--# @param na_rm :: Bool (Optional) Should missing values be removed? Default is false.
--# @param weight :: Vector[Float] | List[Float] = NA Optional non-negative observation weights.
--# @return :: Float The quantile value.
--# @example
--#   quantile(x, 0.5)
--#   -- Returns median
--# @family stats
--# @seealso median, mean
--# @export
*)
let register env =
  Env.add "quantile"
    (make_builtin_named ~name:"quantile" ~variadic:true 2 (fun named_args _env ->
      match Math_common.get_bool_flag "na_rm" false named_args with
      | Error e -> e
      | Ok na_rm ->
      let args = Math_common.positional_args_without ["na_rm"; "weight"] named_args in
      let weight_arg = List.assoc_opt (Some "weight") named_args in
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
      let extract_nums_arr_na_rm label arr =
        let nums = ref [] in
        let had_error = ref None in
        for i = 0 to Array.length arr - 1 do
          if !had_error = None then
            match arr.(i) with
            | VInt n -> nums := float_of_int n :: !nums
            | VFloat f -> nums := f :: !nums
            | VNA _ -> ()
            | _ -> had_error := Some (Error.type_error (Printf.sprintf "Function `%s` requires numeric values." label))
        done;
        match !had_error with Some e -> Error e | None -> Ok (Array.of_list (List.rev !nums))
      in
      let get_p = function
        | VFloat f -> if f < 0.0 || f > 1.0 then None else Some f
        | VInt 0 -> Some 0.0
        | VInt 1 -> Some 1.0
        | _ -> None
      in
      let compute_quantile nums p =
        match Math_utils.quantile_array nums p with
        | Some q -> VFloat q
        | None -> Error.value_error "Function `quantile` called on empty data."
      in
      (match args with
      | [VVector arr; p_val] ->
          (match get_p p_val with
            | None -> Error.value_error "Function `quantile` expects a probability between 0 and 1."
            | Some p ->
              (match weight_arg with
               | Some weight_v ->
                   (match Math_utils.extract_numeric_array_with_weights ~label:"quantile" ~na_rm (VVector arr) weight_v with
                    | Error e -> e
                    | Ok (xs, ws) ->
                        (match Math_utils.weighted_quantile_array xs ws p with
                         | Some q -> VFloat q
                         | None -> VNA NAFloat))
               | None ->
                   if na_rm then
                     (match extract_nums_arr_na_rm "quantile" arr with
                      | Error e -> e
                      | Ok nums when Array.length nums = 0 -> VNA NAFloat
                      | Ok nums -> compute_quantile nums p)
                   else
                     (match extract_nums_arr "quantile" arr with
                      | Error e -> e
                      | Ok nums -> compute_quantile nums p)))
      | [VList items; p_val] ->
          (match get_p p_val with
            | None -> Error.value_error "Function `quantile` expects a probability between 0 and 1."
            | Some p ->
              (match weight_arg with
               | Some weight_v ->
                   (match Math_utils.extract_numeric_array_with_weights ~label:"quantile" ~na_rm (VList items) weight_v with
                    | Error e -> e
                    | Ok (xs, ws) ->
                        (match Math_utils.weighted_quantile_array xs ws p with
                         | Some q -> VFloat q
                         | None -> VNA NAFloat))
               | None ->
                   let arr = Array.of_list (List.map snd items) in
                   if na_rm then
                     (match extract_nums_arr_na_rm "quantile" arr with
                      | Error e -> e
                      | Ok nums when Array.length nums = 0 -> VNA NAFloat
                      | Ok nums -> compute_quantile nums p)
                   else
                     (match extract_nums_arr "quantile" arr with
                      | Error e -> e
                      | Ok nums -> compute_quantile nums p)))
      | [VNA _; _] | [_; VNA _] -> Error.na_value_error ~na_rm:true "quantile"
      | [_; _] -> Error.type_error "Function `quantile` expects a numeric List or Vector as first argument."
      | _ -> Error.arity_error_named "quantile" 2 (List.length args))
    ))
    env
