open Ast

let register ~eval_call env =
  Env.add "mutate"
    (make_builtin 3 (fun args env ->
      match args with
      | [VDataFrame df; VString col_name; fn] ->
          let new_col = Array.init df.nrows (fun i ->
            let row_dict = VDict (List.map (fun (name, col) -> (name, col.(i))) df.columns) in
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
             let existing = List.mem_assoc col_name df.columns in
             let new_columns =
               if existing then
                 List.map (fun (n, c) -> if n = col_name then (n, new_col) else (n, c)) df.columns
               else
                 df.columns @ [(col_name, new_col)]
             in
             VDataFrame { columns = new_columns; nrows = df.nrows; group_keys = df.group_keys })
      | [VDataFrame _; VString _] -> make_error ArityError "mutate() requires a DataFrame, column name, and a function"
      | [VDataFrame _; _; _] -> make_error TypeError "mutate() expects a string column name as second argument"
      | [_; _; _] -> make_error TypeError "mutate() expects a DataFrame as first argument"
      | _ -> make_error ArityError "mutate() takes exactly 3 arguments"
    ))
    env
