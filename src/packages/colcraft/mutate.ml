open Ast

let register ~eval_call env =
  Env.add "mutate"
    (make_builtin 3 (fun args env ->
      match args with
      | [VDataFrame df; VString col_name; VVector vec] ->
          (* Column-level mutate: directly add a vector as a new column *)
          let nrows = Arrow_table.num_rows df.arrow_table in
          if Array.length vec <> nrows then
            make_error ValueError
              (Printf.sprintf "mutate() vector length %d does not match DataFrame row count %d"
                 (Array.length vec) nrows)
          else
            let arrow_col = Arrow_bridge.values_to_column vec in
            let new_table = Arrow_compute.add_column df.arrow_table col_name arrow_col in
            VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
      | [VDataFrame df; VString col_name; fn] ->
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
            (* Ungrouped mutate: apply fn row-by-row *)
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
               VDataFrame { arrow_table = new_table; group_keys = df.group_keys })
      | [VDataFrame _; VString _] -> make_error ArityError "mutate() requires a DataFrame, column name, and a function"
      | [VDataFrame _; _; _] -> make_error TypeError "mutate() expects a string column name as second argument"
      | [_; _; _] -> make_error TypeError "mutate() expects a DataFrame as first argument"
      | _ -> make_error ArityError "mutate() takes exactly 3 arguments"
    ))
    env
