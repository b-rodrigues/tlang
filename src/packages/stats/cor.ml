open Ast

(*
--# Correlation
--#
--# Computes the correlation coefficient between two vectors.
--# `method = "pearson"` (default) is the linear correlation.
--# `method = "spearman"` ranks values first (average ranks for ties),
--# then computes Pearson on ranks.
--#
--# @name cor
--# @param x :: Vector | List First numeric vector.
--# @param y :: Vector | List Second numeric vector.
--# @param na_rm :: Bool (Optional) Should missing values be removed? Default is false.
--# @param weights :: Vector[Float] | List[Float] = NA Optional non-negative observation weights (Pearson only).
--# @param method :: String = "pearson" Correlation method: "pearson" or "spearman".
--# @return :: Float The correlation coefficient (-1 to 1).
--# @example
--#   cor(mtcars["mpg"], mtcars["wt"])
--# @family stats
--# @export
*)
let rank_of_floats xs =
  let n = Array.length xs in
  let idx = Array.init n (fun i -> i) in
  Array.sort (fun a b -> Float.compare xs.(a) xs.(b)) idx;
  let ranks = Array.make n 0.0 in
  (* Mutable scan over the sorted index: groups equal values so tied
     observations share their average rank. A ref loop is the direct
     traversal here. *)
  let i = ref 0 in
  while !i < n do
    let j = ref !i in
    while !j + 1 < n && Float.compare xs.(idx.(!j + 1)) xs.(idx.(!i)) = 0 do
      incr j
    done;
    let avg = (float_of_int (!i + 1) +. float_of_int (!j + 1)) /. 2.0 in
    for k = !i to !j do
      ranks.(idx.(k)) <- avg
    done;
    i := !j + 1
  done;
  ranks

let register env =
  Env.add "cor"
    (make_builtin_named ~name:"cor" ~variadic:true 2 (fun named_args _env ->
      match Math_common.get_bool_flag "na_rm" false named_args with
      | Error e -> e
      | Ok na_rm ->
      let method_arg =
        match List.find_map (fun (k, v) -> if k = Some "method" then Some v else None) named_args with
        | None | Some (Ast.(VNA _)) -> Ok "pearson"
        | Some (Ast.VString s) | Some (Ast.VSymbol s) ->
            let m = String.lowercase_ascii (String.trim s) in
            if m = "pearson" || m = "spearman" then Ok m
            else Error (Error.value_error "Function `cor` method must be \"pearson\" or \"spearman\".")
        | Some _ -> Error (Error.type_error "Function `cor` expects `method` to be a String.")
      in
      (match method_arg with
      | Error e -> e
      | Ok meth ->
      let args = Math_common.positional_args_without ["na_rm"; "weights"; "method"] named_args in
      let weight_arg = Math_common.optional_named_arg "weights" named_args in
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
      let pairwise_delete arr1 arr2 =
        let n = Array.length arr1 in
        let xs = ref [] in
        let ys = ref [] in
        for i = 0 to n - 1 do
          match (arr1.(i), arr2.(i)) with
          | (VNA _, _) | (_, VNA _) -> ()
          | _ -> xs := arr1.(i) :: !xs; ys := arr2.(i) :: !ys
        done;
        (Array.of_list (List.rev !xs), Array.of_list (List.rev !ys))
      in
      let to_arr = function
        | VVector arr -> Some arr
        | VList items -> Some (Array.of_list (List.map snd items))
        | _ -> None
      in
      (match args with
      | [v1; v2] ->
          (match weight_arg with
           | Some _ when meth = "spearman" ->
               Error.value_error "Function `cor` with method \"spearman\" does not support weights. Use method \"pearson\" for weighted correlation."
           | Some weight_v ->
                (match Math_utils.extract_paired_numeric_arrays_with_weights ~label:"cor" ~na_rm v1 v2 weight_v with
                 | Error e -> e
                 | Ok (xs, ys, ws) ->
                     if Array.length xs < 2 then Error.value_error "Function `cor` requires at least 2 paired values."
                     else
                       (match (Math_utils.weighted_covariance_population xs ys ws,
                               Math_utils.weighted_variance_population xs ws,
                               Math_utils.weighted_variance_population ys ws) with
                        | Some cov_xy, Some var_x, Some var_y when var_x > 0.0 && var_y > 0.0 ->
                            VFloat (cov_xy /. Float.sqrt (var_x *. var_y))
                        | Some _, Some _, Some _ ->
                            Error.value_error "Function `cor` undefined: one or both vectors have zero variance."
                        | _ ->
                            Error.make_error RuntimeError "Function `cor` internal error: weighted correlation could not be computed."))
           | None ->
                let pearson_of_floats xs ys =
                  match Arrow_owl_bridge.pearson_cor xs ys with
                  | None ->
                      Error.value_error "Function `cor` undefined: one or both vectors have zero variance."
                  | Some r -> VFloat r
                in
                let correlate_floats xs ys =
                  if meth = "spearman" then
                    pearson_of_floats (rank_of_floats xs) (rank_of_floats ys)
                  else
                    pearson_of_floats xs ys
                in
                (match (to_arr v1, to_arr v2) with
                 | (None, _) | (_, None) ->
                     (match (v1, v2) with
                      | (VNA _, _) | (_, VNA _) -> Error.na_value_error ~na_rm:true "cor"
                      | _ -> Error.type_error "Function `cor` expects two numeric Vectors or Lists.")
                 | (Some arr1, Some arr2) ->
                   if Array.length arr1 <> Array.length arr2 then
                     Error.value_error "Function `cor` requires vectors of equal length."
                   else if na_rm then
                     let (clean1, clean2) = pairwise_delete arr1 arr2 in
                     if Array.length clean1 < 2 then
                       if Array.length clean1 = 0 then VNA NAFloat
                       else Error.value_error "Function `cor` requires at least 2 non-NA pairs."
                     else
                       (match (extract_nums_arr "cor" clean1, extract_nums_arr "cor" clean2) with
                        | (Error e, _) | (_, Error e) -> e
                        | (Ok xs, Ok ys) -> correlate_floats xs ys)
                   else if Array.length arr1 < 2 then
                     Error.value_error "Function `cor` requires at least 2 values."
                   else
                     (match (extract_nums_arr "cor" arr1, extract_nums_arr "cor" arr2) with
                      | (Error e, _) | (_, Error e) -> e
                      | (Ok xs, Ok ys) -> correlate_floats xs ys)))
      | _ -> Error.arity_error_named "cor" 2 (List.length args)))
    ))
    env
