open Ast

let register env =
  Env.add "glimpse"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { arrow_table; group_keys }] ->
          let nrows = Arrow_table.num_rows arrow_table in
          let ncols = Arrow_table.num_columns arrow_table in
          let value_columns = Arrow_bridge.table_to_value_columns arrow_table in
          let col_info = VList (List.map (fun (name, col) ->
            let col_type = ref "Unknown" in
            Array.iter (fun v ->
              if !col_type = "Unknown" then
                match v with VNA _ -> () | _ -> col_type := Utils.type_name v
            ) col;
            let example_n = min 3 (Array.length col) in
            let examples = List.init example_n (fun i ->
              Utils.value_to_string col.(i)
            ) in
            let example_str = String.concat ", " examples in
            (None, VString (Printf.sprintf "%s <%s> %s" name !col_type example_str))
          ) value_columns) in
          let grouped_info =
            if group_keys = [] then []
            else [("group_keys", VList (List.map (fun k -> (None, VString k)) group_keys))]
          in
          VDict ([
            ("kind", VString "dataframe");
            ("nrow", VInt nrows);
            ("ncol", VInt ncols);
            ("columns", col_info);
          ] @ grouped_info)
      | [VNA _] -> make_error TypeError "glimpse() expects a DataFrame, got NA"
      | [_] -> make_error TypeError "glimpse() expects a DataFrame"
      | _ -> make_error ArityError "glimpse() takes exactly 1 argument"
    ))
    env
