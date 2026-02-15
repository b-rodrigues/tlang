open Ast

let register ~eval_call ~eval_expr:(_eval_expr : Ast.value Ast.Env.t -> Ast.expr -> Ast.value) ~uses_nse:(_uses_nse : Ast.expr -> bool) ~desugar_nse_expr:(_desugar_nse_expr : Ast.expr -> Ast.expr) env =
  (*
  --# Create or modify columns
  --#
  --# Adds new columns or modifies existing ones.
  --#
  --# @name mutate
  --# @param df :: DataFrame The input DataFrame.
  --# @param ... :: KeywordArgs New columns as name = expression pairs.
  --# @return :: DataFrame The modified DataFrame.
  --# @example
  --#   mutate(mtcars, $hp_per_wt = $hp / $wt)
  --# @family colcraft
  --# @seealso summarize, select
  --# @export
  *)
  Env.add "mutate"
    (make_builtin_named ~variadic:true 1 (fun named_args env ->
      (* Helper: apply a single mutation (col_name, fn) to a DataFrame *)
      let apply_mutation df col_name fn =
        let nrows = Arrow_table.num_rows df.arrow_table in
        if df.group_keys <> [] then
          (* Grouped mutate: pass group sub-DataFrame to fn, broadcast result *)
          let grouped = Arrow_compute.group_by df.arrow_table df.group_keys in
          let groups = grouped.Arrow_compute.ocaml_groups in
          let new_col = Array.make nrows VNull in
          let had_error = ref None in
          List.iter (fun (_, row_indices) ->
            if !had_error = None then begin
              let sub_table = Arrow_compute.take_rows df.arrow_table row_indices in
              let sub_df = VDataFrame { arrow_table = sub_table; group_keys = [] } in
              let result = eval_call env fn [(None, Value sub_df)] in
              match result with
              | VError _ -> had_error := Some result
              | VVector vec when Array.length vec = List.length row_indices ->
                List.iteri (fun i idx -> new_col.(idx) <- vec.(i)) row_indices
              | _ ->
                List.iter (fun idx -> new_col.(idx) <- result) row_indices
            end
          ) groups;
          (match !had_error with
           | Some e -> e
           | None ->
             let arrow_col = Arrow_bridge.values_to_column new_col in
             let new_table = Arrow_compute.add_column df.arrow_table col_name arrow_col in
             VDataFrame { arrow_table = new_table; group_keys = df.group_keys })
        else
          (* Try whole-DataFrame evaluation first for window functions.
             Falls back to row-by-row if result isn't a VVector/VList of correct length. *)
          let whole_result = eval_call env fn [(None, Value (VDataFrame df))] in
          (match whole_result with
            | VVector vec when Array.length vec = nrows ->
              let arrow_col = Arrow_bridge.values_to_column vec in
              let new_table = Arrow_compute.add_column df.arrow_table col_name arrow_col in
              VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
            | VList items when List.length items = nrows ->
              let vec = Array.of_list (List.map snd items) in
              let arrow_col = Arrow_bridge.values_to_column vec in
              let new_table = Arrow_compute.add_column df.arrow_table col_name arrow_col in
              VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
            | res when not (is_na_value res) && (match res with VVector _ | VList _ | VNDArray _ | VError _ -> false | _ -> true) ->
              (* Broadcast scalar result *)
              let vec = Array.make nrows res in
              let arrow_col = Arrow_bridge.values_to_column vec in
              let new_table = Arrow_compute.add_column df.arrow_table col_name arrow_col in
              VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
            | _ ->
              (* Fallback: apply fn row-by-row (handles VError or mismatched lengths) *)
             let new_col = Array.init nrows (fun i ->
               let row_dict = VDict (Arrow_bridge.row_to_dict df.arrow_table i) in
               eval_call env fn [(None, Value row_dict)]
             ) in
             let first_error = ref None in
             Array.iter (fun v ->
               if !first_error = None then
                 match v with VError _ -> first_error := Some v | _ -> ()
             ) new_col;
             (match !first_error with
              | Some e -> e
              | None ->
                let arrow_col = Arrow_bridge.values_to_column new_col in
                let new_table = Arrow_compute.add_column df.arrow_table col_name arrow_col in
                VDataFrame { arrow_table = new_table; group_keys = df.group_keys }))
      in
      (* Helper: apply a vector mutation directly *)
      let apply_vector_mutation df col_name vec =
        let nrows = Arrow_table.num_rows df.arrow_table in
        if Array.length vec <> nrows then
          Error.value_error
            (Printf.sprintf "Function `mutate` vector length %d does not match DataFrame row count %d."
               (Array.length vec) nrows)
        else
          let arrow_col = Arrow_bridge.values_to_column vec in
          let new_table = Arrow_compute.add_column df.arrow_table col_name arrow_col in
          VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
      in
      match named_args with
      (* Named arg syntax: mutate(df, $col = expr, ...) *)
      | (_, VDataFrame df) :: rest when rest <> [] ->
          let rec apply_named_mutations current_df = function
            | [] -> VDataFrame current_df
            | (Some col_name, VVector vec) :: rest_mutations ->
                (match apply_vector_mutation current_df col_name vec with
                 | VDataFrame new_df -> apply_named_mutations new_df rest_mutations
                 | err -> err)
            | (Some col_name, fn) :: rest_mutations ->
                (match apply_mutation current_df col_name fn with
                 | VDataFrame new_df -> apply_named_mutations new_df rest_mutations
                 | err -> err)
            | (None, _) :: _ ->
                Error.type_error "Function `mutate` expects $column = expr syntax."
          in
          apply_named_mutations df rest
      | (_, VDataFrame _) :: [] -> Error.make_error ArityError "Function `mutate` requires at least one $column = expr argument."
      | [(_, _); _; _] | [(_, _); _] -> Error.type_error "Function `mutate` expects a DataFrame as first argument."
      | _ -> Error.make_error ArityError "Function `mutate` expects a DataFrame and $col = expr arguments."
    ))
    env
