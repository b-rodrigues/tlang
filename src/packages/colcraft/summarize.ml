open Ast

(** Detect if a value is a vectorizable aggregation.
    Inspects the lambda body for patterns like:
      \(row) agg_fn(row.col)           — simple aggregation
      \(row) agg_fn(row.col, na_rm=T)  — aggregation with na_rm
    Returns Some(agg_name, col_name, na_rm) when the function can be
    delegated to Arrow_compute column aggregations or group_aggregate. *)
let detect_vectorizable_agg (fn : value) : (string * string * bool) option =
  match fn with
  | VLambda { params = [param]; body; _ } ->
    (match body.node with
     (* Pattern: n(row) — inserted by eval for summarize($x = n()) *)
     | Call { fn = { node = Var "n"; _ }; args = [(None, { node = Var p; _ })] }
       when p = param ->
       Some ("n", "", false)
     (* Pattern: agg(row.col) *)
     | Call { fn = { node = Var agg_name; _ };
              args = [(None, { node = DotAccess { target = { node = Var p; _ }; field }; _ })] }
        when p = param ->
        (match agg_name with
         | "mean" | "sum" | "min" | "max" | "count" | "nrow" | "n_distinct" -> Some (agg_name, field, false)
         | _ -> None)
     (* Pattern: agg(row.col, na_rm = true) *)
     | Call { fn = { node = Var agg_name; _ };
              args = [(None, { node = DotAccess { target = { node = Var p; _ }; field }; _ });
                      (Some "na_rm", { node = Value (VBool true); _ })] }
        when p = param ->
        (match agg_name with
         | "mean" | "sum" | "min" | "max" | "count" | "nrow" -> Some (agg_name, field, true)
         | _ -> None)
     | _ -> None)
  | _ -> None

(** Check whether a column contains any null/NA values.
    Used to decide whether the vectorized aggregation path is safe
    when na_rm is not explicitly set (default na_rm=false errors on NAs). *)
let column_has_nulls (table : Arrow_table.t) (col_name : string) : bool =
  match Arrow_table.get_column table col_name with
  | Some (Arrow_table.FloatColumn a) ->
    let n = Array.length a in
    let rec check i = if i >= n then false
      else match a.(i) with None -> true | Some _ -> check (i + 1)
    in check 0
  | Some (Arrow_table.IntColumn a) ->
    let n = Array.length a in
    let rec check i = if i >= n then false
      else match a.(i) with None -> true | Some _ -> check (i + 1)
    in check 0
  | Some (Arrow_table.NullColumn _) -> true
  | None -> true
  | _ -> true

let column_has_nulls_cached
    (table : Arrow_table.t)
    (null_cache : (string, bool) Hashtbl.t)
    (col_name : string) : bool =
  match Hashtbl.find_opt null_cache col_name with
  | Some has_nulls -> has_nulls
  | None ->
    let has_nulls = column_has_nulls table col_name in
    Hashtbl.replace null_cache col_name has_nulls;
    has_nulls

let can_vectorize_agg
    (table : Arrow_table.t)
    (null_cache : (string, bool) Hashtbl.t)
    (agg_name : string)
    (col_name : string)
    (na_rm : bool) : bool =
  match agg_name with
  | "n" | "n_distinct" -> true
  | _ -> na_rm || not (column_has_nulls_cached table null_cache col_name)

let finalize_vectorized_agg_value (agg_name : string) (value : value) : value =
  match agg_name, value with
  | ("n" | "count" | "nrow" | "n_distinct"), VFloat f -> VInt (int_of_float f)
  | _ -> value

let finalize_vectorized_agg_values (agg_name : string) (values : value array) : value array =
  match agg_name with
  | "n" | "count" | "nrow" | "n_distinct" ->
      Array.map (finalize_vectorized_agg_value agg_name) values
  | _ -> values

let register ~eval_call ~eval_expr:(_eval_expr : Ast.value Ast.Env.t -> Ast.expr -> Ast.value) ~uses_nse:(_uses_nse : Ast.expr -> bool) ~desugar_nse_expr:(_desugar_nse_expr : Ast.expr -> Ast.expr) env =
  (* Helper: apply aggregation fn with arg if callable, otherwise use fn as a constant value *)
  let apply_aggregation env fn arg =
    match fn with
    | VLambda _ | VBuiltin _ -> eval_call env fn [(None, Ast.mk_expr (Value arg))]
    | v -> v
  in
  (*
  --# Summarize data
  --#
  --# Aggregates a DataFrame to a single row (or one row per group).
  --#
  --# @name summarize
  --# @param df :: DataFrame The input DataFrame.
  --# @param ... :: KeywordArgs Aggregations as name = expression pairs.
  --# @return :: DataFrame The summarized DataFrame.
  --# @example
  --#   summarize(mtcars, $mean_mpg = mean($mpg))
  --#   summarize(group_by(mtcars, $cyl), $mean_hp = mean($hp))
  --# @family colcraft
  --# @seealso group_by, mutate
  --# @export
  *)
  Env.add "summarize"
    (make_builtin_named ~name:"summarize" ~variadic:true 1 (fun named_args env ->
      match named_args with
      | (_, VDataFrame df) :: rest_args ->
          (* Parse named args: summarize(df, $total = sum($amount), ...) *)
          let rec parse_pairs acc = function
            | (Some name, fn) :: rest ->
                parse_pairs ((name, fn) :: acc) rest
            | [] -> Ok (List.rev acc)
            | _ -> Error (Error.type_error "Function `summarize` expects $column = expr syntax.")
          in
          (match parse_pairs [] rest_args with
           | Error e -> e
           | Ok pairs ->
              let null_cache = Hashtbl.create (max 1 (List.length pairs)) in
              if pairs = [] then
                Error.make_error ArityError "Function `summarize` requires at least one $column = expr argument."
              else if df.group_keys = [] then
                (* Ungrouped summarize: try vectorized path for each aggregation *)
                let result_cols = List.map (fun (name, fn) ->
                  match detect_vectorizable_agg fn with
                  | Some (agg_name, col_name, na_rm) ->
                    (* Vectorized path: use Arrow compute column aggregation *)
                    let can_vectorize =
                      can_vectorize_agg df.arrow_table null_cache agg_name col_name na_rm
                    in
                    if can_vectorize then
                      let agg_fn = match agg_name with
                        | "mean" -> Arrow_compute.mean_column
                        | "sum"  -> Arrow_compute.sum_column
                        | "min"  -> Arrow_compute.min_column
                        | "max"  -> Arrow_compute.max_column
                        | "n_distinct" -> Arrow_compute.count_distinct_column
                        | "n" -> (fun t _c -> Some (float_of_int (Arrow_table.num_rows t)))
                        | "count" | "nrow" -> (fun t _c -> Some (float_of_int (Arrow_table.num_rows t))) (* Count of whole table if ungrouped *)
                        | _ -> (fun _ _ -> None)
                      in
                      (match agg_fn df.arrow_table col_name with
                       | Some f -> (name, finalize_vectorized_agg_value agg_name (VFloat f))
                       | None ->
                          (* Native compute failed — fall back *)
                          (name, apply_aggregation env fn (VDataFrame df)))
                   else
                     (* Column has NAs and na_rm not set — fall back for correct error *)
                     (name, apply_aggregation env fn (VDataFrame df))
                 | None ->
                   (name, apply_aggregation env fn (VDataFrame df))
               ) pairs in
               (match List.find_opt (fun (_, v) -> is_error_value v) result_cols with
                | Some (_, e) -> e
                | None ->
                  let value_columns = List.map (fun (name, v) -> (name, [|v|])) result_cols in
                  let arrow_table = Arrow_bridge.table_from_value_columns value_columns 1 in
                  VDataFrame { arrow_table; group_keys = [] })
               else
                 let grouped = Arrow_compute.group_by df.arrow_table df.group_keys in
                let vectorized_pairs =
                  List.map (fun (name, fn) ->
                    match detect_vectorizable_agg fn with
                    | Some (agg_name, col_name, na_rm)
                      when can_vectorize_agg df.arrow_table null_cache agg_name col_name na_rm ->
                      let agg_name_eff =
                        match agg_name with
                        | "nrow" | "n" -> "count"
                        | "n_distinct" -> "count_distinct"
                        | _ -> agg_name
                      in
                      Some (name, fn, agg_name, agg_name_eff, col_name)
                    | _ -> None
                  ) pairs
                in
                let rec collect_if_all_vectorizable acc = function
                  | [] -> Some (List.rev acc)
                  | Some spec :: rest -> collect_if_all_vectorizable (spec :: acc) rest
                  | None :: _ -> None
                in
                (match collect_if_all_vectorizable [] vectorized_pairs with
                | Some specs ->
                  (match specs with
                   | [] ->
                     Error.make_error ArityError "Function `summarize` requires at least one $column = expr argument."
                   | _ ->
                     (* Build multi-aggregate specs: (agg_type, input_col, output_name) *)
                     let multi_specs = List.map (fun (name, _fn, _agg, agg_eff, col) ->
                       let input_col = if agg_eff = "count" then "" else col in
                       (agg_eff, input_col, name)
                     ) specs in
                     (* Try batch multi-aggregate (builds key columns once) *)
                     let result_table =
                       match Arrow_compute.group_multi_aggregate grouped multi_specs with
                       | Some t -> t
                       | None ->
                         (* Fallback: sequential single-aggregate calls *)
                         let (first_name, _, _first_agg, first_agg_eff, first_col) = List.hd specs in
                         let rest_specs = List.tl specs in
                         let first_res = Arrow_compute.group_aggregate grouped first_agg_eff first_col in
                         let first_col_key = if first_agg_eff = "count" then "n" else first_col in
                         let base_table = Arrow_table.rename_columns first_res [(first_name, first_col_key)] in
                         List.fold_left (fun acc (name, _fn, _agg, agg_eff, col) ->
                           let res_table = Arrow_compute.group_aggregate grouped agg_eff col in
                           let res_col_key = if agg_eff = "count" then "n" else col in
                           Arrow_table.add_column_from_table acc name res_table res_col_key
                         ) base_table rest_specs
                     in
                     VDataFrame { arrow_table = result_table; group_keys = [] })
                | None ->
                  let groups = Arrow_compute.get_ocaml_groups grouped in
                  let n_groups = List.length groups in
                  (* Convert groups to array: List.nth is O(n) per call; *)
                  (* using an array gives O(1) indexed access per group  *)
                  let groups_array = Array.of_list groups in
                  let key_col_values = List.map (fun k ->
                    match Arrow_table.get_column df.arrow_table k with
                    | Some col -> (k, Arrow_bridge.column_to_values col)
                    | None -> (k, [||])
                  ) df.group_keys in
                  let key_result_cols = List.map (fun k ->
                    let col = Array.init n_groups (fun g_idx ->
                      let (_, indices) = groups_array.(g_idx) in
                      match indices with
                      | first :: _ ->
                        let (_, key_vals) = List.find (fun (kn, _) -> kn = k) key_col_values in
                        if first < Array.length key_vals then key_vals.(first) else VNull
                      | [] -> VNull
                    ) in
                    (k, col)
                  ) df.group_keys in
                  (* Batch all vectorizable aggs into one multi_aggregate call *)
                  let vectorizable_specs = List.filter_map (fun (name, fn) ->
                    match detect_vectorizable_agg fn with
                    | Some (agg_name, col_name, na_rm)
                      when can_vectorize_agg df.arrow_table null_cache agg_name col_name na_rm ->
                      let agg_name_eff = match agg_name with
                        | "nrow" | "n" -> "count"
                        | "n_distinct" -> "count_distinct"
                        | _ -> agg_name
                      in
                      Some (name, agg_name, agg_name_eff, col_name)
                    | _ -> None
                  ) pairs in
                  let batch_result =
                    if vectorizable_specs <> [] then
                      let multi_specs = List.map (fun (name, _agg, agg_eff, col) ->
                        let input_col = if agg_eff = "count" then "" else col in
                        (agg_eff, input_col, name)
                      ) vectorizable_specs in
                      Arrow_compute.group_multi_aggregate grouped multi_specs
                    else None
                  in
                  let had_error = ref None in
                  let summary_result_cols = List.map (fun (name, fn) ->
                    if !had_error <> None then (name, Array.make n_groups VNull)
                    else
                      match detect_vectorizable_agg fn with
                      | Some (agg_name, col_name, na_rm) ->
                        let can_vectorize =
                          can_vectorize_agg df.arrow_table null_cache agg_name col_name na_rm
                        in
                        if can_vectorize then
                          (* Try extracting from batch result first *)
                          let from_batch = match batch_result with
                            | Some batch_table ->
                              (match Arrow_table.get_column batch_table name with
                               | Some col ->
                                 let values = Arrow_bridge.column_to_values col in
                                 Some (name, finalize_vectorized_agg_values agg_name values)
                               | None -> None)
                            | None -> None
                          in
                          (match from_batch with
                           | Some result -> result
                           | None ->
                             (* Fallback: individual group_aggregate *)
                             let agg_name_eff = match agg_name with
                               | "nrow" | "n" -> "count"
                               | "n_distinct" -> "count_distinct"
                               | _ -> agg_name
                             in
                             let result_table = Arrow_compute.group_aggregate grouped agg_name_eff col_name in
                             let result_col_key = if agg_name_eff = "count" then "n" else col_name in
                             (match Arrow_table.get_column result_table result_col_key with
                              | Some col ->
                                let values = Arrow_bridge.column_to_values col in
                                (name, finalize_vectorized_agg_values agg_name values)
                              | None ->
                                let col = Array.init n_groups (fun g_idx ->
                                  let (_, row_indices) = groups_array.(g_idx) in
                                  let sub_table = Arrow_compute.take_rows df.arrow_table row_indices in
                                  let sub_df = VDataFrame { arrow_table = sub_table; group_keys = [] } in
                                  let result = apply_aggregation env fn sub_df in
                                  (match result with
                                   | VError _ -> had_error := Some result; result
                                   | v -> v)
                                ) in
                                (name, col)))
                        else
                          (* Column has NAs — fall back to per-group for correct error *)
                          let col = Array.init n_groups (fun g_idx ->
                            if !had_error <> None then VNull
                            else begin
                              let (_, row_indices) = groups_array.(g_idx) in
                              let sub_table = Arrow_compute.take_rows df.arrow_table row_indices in
                              let sub_df = VDataFrame { arrow_table = sub_table; group_keys = [] } in
                              let result = apply_aggregation env fn sub_df in
                              (match result with
                               | VError _ -> had_error := Some result; result
                               | v -> v)
                            end
                          ) in
                          (name, col)
                      | None ->
                        (* Non-vectorizable — per-group evaluation *)
                        let col = Array.init n_groups (fun g_idx ->
                          if !had_error <> None then VNull
                          else begin
                            let (_, row_indices) = groups_array.(g_idx) in
                            let sub_table = Arrow_compute.take_rows df.arrow_table row_indices in
                            let sub_df = VDataFrame { arrow_table = sub_table; group_keys = [] } in
                            let result = apply_aggregation env fn sub_df in
                            (match result with
                             | VError _ -> had_error := Some result; result
                             | v -> v)
                          end
                        ) in
                        (name, col)
                  ) pairs in
                  (match !had_error with
                   | Some e -> e
                   | None ->
                     let all_columns = key_result_cols @ summary_result_cols in
                     let arrow_table = Arrow_bridge.table_from_value_columns all_columns n_groups in
                     VDataFrame { arrow_table; group_keys = [] })))
      | _ -> Error.type_error "Function `summarize` expects a DataFrame as first argument."
    ))
    env
