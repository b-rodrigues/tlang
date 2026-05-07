open Ast

(*
--# Standard Deviation
--#
--# Calculates the sample standard deviation of a numeric vector.
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
      let weight_arg = List.assoc_opt (Some "weights") named_args in
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
      let compute_sd nums n =
        if n < 2 then Error.value_error "Function `sd` requires at least 2 values."
        else
          let mean = Array.fold_left ( +. ) 0.0 nums /. float_of_int n in
          let sum_sq = Array.fold_left (fun acc x -> acc +. (x -. mean) *. (x -. mean)) 0.0 nums in
          VFloat (Float.sqrt (sum_sq /. float_of_int (n - 1)))
      in
      let first_arg = match args with a :: _ -> Some a | [] -> None in
      (match first_arg with
      | Some (VList items) ->
          (match weight_arg with
           | Some weight_v ->
               (match Math_utils.extract_numeric_array_with_weights ~label:"sd" ~na_rm (VList items) weight_v with
                | Error e -> e
                | Ok (xs, ws) ->
                    if Array.length xs < 2 then Error.value_error "Function `sd` requires at least 2 values."
                    else
                      (match Math_utils.weighted_variance_population xs ws with
                       | Some v -> VFloat (Float.sqrt v)
                       | None -> Error.make_error RuntimeError "Function `sd` internal error: weighted variance could not be computed."))
           | None ->
               let arr = Array.of_list (List.map snd items) in
               if na_rm then
                 (match extract_nums_arr_na_rm "sd" arr with
                  | Error e -> e
                  | Ok nums when Array.length nums = 0 -> VNA NAFloat
                  | Ok nums -> compute_sd nums (Array.length nums))
               else
                 (match extract_nums_arr "sd" arr with
                  | Error e -> e
                  | Ok nums -> compute_sd nums (Array.length nums)))
      | Some (VVector arr) ->
          (match weight_arg with
           | Some weight_v ->
               (match Math_utils.extract_numeric_array_with_weights ~label:"sd" ~na_rm (VVector arr) weight_v with
                | Error e -> e
                | Ok (xs, ws) ->
                    if Array.length xs < 2 then Error.value_error "Function `sd` requires at least 2 values."
                    else
                      (match Math_utils.weighted_variance_population xs ws with
                       | Some v -> VFloat (Float.sqrt v)
                       | None -> Error.make_error RuntimeError "Function `sd` internal error: weighted variance could not be computed."))
           | None ->
               if na_rm then
                 (match extract_nums_arr_na_rm "sd" arr with
                  | Error e -> e
                  | Ok nums when Array.length nums = 0 -> VNA NAFloat
                  | Ok nums -> compute_sd nums (Array.length nums))
               else
                 (match extract_nums_arr "sd" arr with
                  | Error e -> e
                  | Ok nums -> compute_sd nums (Array.length nums)))
      | Some (VNA _) -> Error.na_value_error ~na_rm:true "sd"
      | Some _ -> Error.type_error "Function `sd` expects a numeric List or Vector."
      | None -> Error.arity_error_named "sd" 1 (List.length args))
    ))
    env
