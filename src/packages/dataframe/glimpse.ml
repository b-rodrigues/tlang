open Ast

let register env =
  Env.add "glimpse"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { arrow_table; _ }] ->
          let nrows = Arrow_table.num_rows arrow_table in
          let ncols = Arrow_table.num_columns arrow_table in
          let value_columns = Arrow_bridge.table_to_value_columns arrow_table in
          
          Printf.printf "Rows: %d\n" nrows;
          Printf.printf "Columns: %d\n" ncols;
          
          List.iter (fun (name, col) ->
            let col_type = ref "Unknown" in
            (* Determine type from first non-NA value *)
            let found_type = ref false in
            let i = ref 0 in
            let len = Array.length col in
            while not !found_type && !i < len do
              match col.(!i) with
              | VNA _ -> i := !i + 1
              | v -> 
                  col_type := Utils.type_name v;
                  found_type := true
            done;
            (* Fallback if all NA *)
            if not !found_type && len > 0 then col_type := "NA";

            let example_n = min 10 (Array.length col) in
            let examples = List.init example_n (fun i ->
              Utils.value_to_string col.(i)
            ) in
            let example_str = String.concat ", " examples in
            let suffix = if Array.length col > 10 then ", ..." else "" in
            Printf.printf "$ %-13s <%s> %s%s\n" name !col_type example_str suffix
          ) value_columns;
          
          flush stdout;
          VNull
      | [VNA _] -> make_error TypeError "glimpse() expects a DataFrame, got NA"
      | [_] -> make_error TypeError "glimpse() expects a DataFrame"
      | _ -> make_error ArityError "glimpse() takes exactly 1 argument"
    ))
    env
