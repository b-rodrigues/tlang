open Ast

(** Detect if a value is a known simple aggregation builtin.
    Returns Some(agg_name) if the function can be delegated to
    Arrow_compute.group_aggregate, None otherwise. *)
let _detect_simple_agg (_fn : value) : string option =
  (* Conservative check: we can't easily identify builtins by function
     pointer in OCaml. Future improvement: tag builtins with names.
     For now, always return None — complex expressions fall back to
     the manual implementation. *)
  None

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
               let result_cols = List.map (fun (name, fn) ->
                 let result = apply_aggregation env fn (VDataFrame df) in
                 (name, result)
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
               let key_col_values = List.map (fun k ->
                 match Arrow_table.get_column df.arrow_table k with
                 | Some col -> (k, Arrow_bridge.column_to_values col)
                 | None -> (k, [||])
               ) df.group_keys in
               let key_result_cols = List.map (fun k ->
                 let col = Array.init n_groups (fun g_idx ->
                   let (_, indices) = List.nth groups g_idx in
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
                 let col = Array.init n_groups (fun g_idx ->
                   if !had_error <> None then VNull
                   else begin
                     let (_, row_indices) = List.nth groups g_idx in
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
