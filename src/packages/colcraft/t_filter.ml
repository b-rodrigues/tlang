open Ast

let register ~eval_call env =
  Env.add "filter"
    (make_builtin 2 (fun args env ->
      match args with
      | [VDataFrame df; fn] ->
          let nrows = Arrow_table.num_rows df.arrow_table in
          let keep = Array.make nrows false in
          let had_error = ref None in
          for i = 0 to nrows - 1 do
            if !had_error = None then begin
              let row_dict = VDict (Arrow_bridge.row_to_dict df.arrow_table i) in
              let result = eval_call env fn [(None, Value row_dict)] in
              match result with
              | VBool true -> keep.(i) <- true
              | VBool false -> ()
              | VError _ as e -> had_error := Some e
              | _ -> had_error := Some (make_error TypeError "filter() predicate must return a Bool")
            end
          done;
          (match !had_error with
           | Some e -> e
           | None ->
             let new_table = Arrow_compute.filter df.arrow_table keep in
             VDataFrame { arrow_table = new_table; group_keys = df.group_keys })
      | [VDataFrame _] -> make_error ArityError "filter() requires a DataFrame and a predicate function"
      | [_; _] -> make_error TypeError "filter() expects a DataFrame as first argument"
      | _ -> make_error ArityError "filter() takes exactly 2 arguments"
    ))
    env
