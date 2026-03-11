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
    (match body with
     (* Pattern: agg(row.col) *)
     | Call { fn = Var agg_name;
              args = [(None, DotAccess { target = Var p; field })] }
       when p = param ->
       (match agg_name with
        | "mean" | "sum" | "min" | "max" | "count" | "nrow" -> Some (agg_name, field, false)
        | _ -> None)
     (* Pattern: agg(row.col, na_rm = true) *)
     | Call { fn = Var agg_name;
              args = [(None, DotAccess { target = Var p; field });
                      (Some "na_rm", Value (VBool true))] }
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

let register ~eval_call ~eval_expr:(_eval_expr : Ast.value Ast.Env.t -> Ast.expr -> Ast.value) ~uses_nse:(_uses_nse : Ast.expr -> bool) ~desugar_nse_expr:(_desugar_nse_expr : Ast.expr -> Ast.expr) env =
  (* Helper: apply aggregation fn with arg if callable, otherwise use fn as a constant value *)
  let apply_aggregation env fn arg =
    match fn with
    | VLambda _ | VBuiltin _ -> eval_call env fn [(None, Value arg)]
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
             if pairs = [] then
               Error.make_error ArityError "Function `summarize` requires at least one $column = expr argument."
             else if df.group_keys = [] then
               (* Ungrouped summarize: try vectorized path for each aggregation *)
               let result_cols = List.map (fun (name, fn) ->
                 match detect_vectorizable_agg fn with
                 | Some (agg_name, col_name, na_rm) ->
                   (* Vectorized path: use Arrow compute column aggregation *)
                   let can_vectorize = na_rm || not (column_has_nulls df.arrow_table col_name) in
                   if can_vectorize then
                     let agg_fn = match agg_name with
                       | "mean" -> Arrow_compute.mean_column
                       | "sum"  -> Arrow_compute.sum_column
                       | "min"  -> Arrow_compute.min_column
                       | "max"  -> Arrow_compute.max_column
                       | "count" | "nrow" -> (fun t _c -> Some (float_of_int (Arrow_table.num_rows t))) (* Count of whole table if ungrouped *)
                       | _ -> (fun _ _ -> None)
                     in
                     (match agg_fn df.arrow_table col_name with
                      | Some f -> (name, VFloat f)
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
               let groups = grouped.Arrow_compute.ocaml_groups in
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
               let had_error = ref None in
               let summary_result_cols = List.map (fun (name, fn) ->
                 if !had_error <> None then (name, Array.make n_groups VNull)
                 else
                   match detect_vectorizable_agg fn with
                   | Some (agg_name, col_name, na_rm) ->
                     (* Vectorized grouped aggregation via Arrow_compute.group_aggregate *)
                      let can_vectorize = na_rm || not (column_has_nulls df.arrow_table col_name) in
                      if can_vectorize then
                        let agg_name_eff = if agg_name = "nrow" then "count" else agg_name in
                        let result_table = Arrow_compute.group_aggregate grouped agg_name_eff col_name in
                        let result_col_key = if agg_name_eff = "count" then "n" else col_name in
                       (match Arrow_table.get_column result_table result_col_key with
                        | Some col ->
                          let values = Arrow_bridge.column_to_values col in
                          (name, values)
                        | None ->
                          (* Native group_aggregate failed — fall back to per-group *)
                          let col = Array.init n_groups (fun g_idx ->
                            let (_, row_indices) = groups_array.(g_idx) in
                            let sub_table = Arrow_compute.take_rows df.arrow_table row_indices in
                            let sub_df = VDataFrame { arrow_table = sub_table; group_keys = [] } in
                            let result = apply_aggregation env fn sub_df in
                            (match result with
                             | VError _ -> had_error := Some result; result
                             | v -> v)
                          ) in
                          (name, col))
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
                  VDataFrame { arrow_table; group_keys = [] }))
      | _ -> Error.type_error "Function `summarize` expects a DataFrame as first argument."
    ))
    env
