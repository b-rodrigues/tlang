open Ast

let register env =
  Env.add "dataframe"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VList rows] ->
          (match rows with
           | [] -> VDataFrame { arrow_table = Arrow_table.empty; group_keys = [] }
           | (_first_row_name, first_row_val) :: _ ->
               (* Inspect first row to determine columns *)
               (match first_row_val with
                | VDict pairs ->
                    let headers = List.map fst pairs in
                    let _ncols = List.length headers in
                    let nrows = List.length rows in
                    
                    (* Extract data for each column from VDict rows *)
                    let columns = List.map (fun col_name ->
                      let col_values = Array.init nrows (fun i ->
                        let (_, row_val) = List.nth rows i in
                        match row_val with
                        | VDict row_pairs ->
                            (match List.assoc_opt col_name row_pairs with
                             | Some v -> v
                             | None -> VNA NAGeneric) (* Missing key = NA *)
                        | _ -> VNA NAGeneric (* Invalid row structure handling *)
                      ) in
                      (col_name, col_values)
                    ) headers in

                    (* Create Arrow table using bridge *)
                    let arrow_table = Arrow_bridge.table_from_value_columns columns nrows in
                    VDataFrame { arrow_table; group_keys = [] }

                | VList pairs ->
                    let headers = List.filter_map (fun (k, _) -> k) pairs in
                    let _ncols = List.length headers in
                    let nrows = List.length rows in
                    
                    (* Extract data for each column from VList rows *)
                    let columns = List.map (fun col_name ->
                      let col_values = Array.init nrows (fun i ->
                        let (_, row_val) = List.nth rows i in
                        match row_val with
                        | VList row_pairs ->
                            (* For VList, find the item with the matching name *)
                            (match List.find_opt (fun (n, _) -> n = Some col_name) row_pairs with
                             | Some (_, v) -> v
                             | None -> VNA NAGeneric)
                        | _ -> VNA NAGeneric (* Invalid row structure handling *)
                      ) in
                      (col_name, col_values)
                    ) headers in

                    (* Create Arrow table using bridge *)
                    let arrow_table = Arrow_bridge.table_from_value_columns columns nrows in
                    VDataFrame { arrow_table; group_keys = [] }
                
                | _ -> Error.type_error (Printf.sprintf "Function `dataframe` expects a list of Dicts (rows). First row is: %s" (Ast.Utils.value_to_string first_row_val))))
                
      | _ -> Error.type_error (Printf.sprintf "Function `dataframe` expects a single argument (List of Dicts). Received: %s" (String.concat ", " (List.map Ast.Utils.value_to_string args)))
    ))
    env
