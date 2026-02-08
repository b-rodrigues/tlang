open Ast

let register ~make_builtin ~make_error ~eval_call env =
  Env.add "filter"
    (make_builtin 2 (fun args env ->
      match args with
      | [VDataFrame df; fn] ->
          let keep = Array.make df.nrows false in
          let had_error = ref None in
          for i = 0 to df.nrows - 1 do
            if !had_error = None then begin
              let row_dict = VDict (List.map (fun (name, col) -> (name, col.(i))) df.columns) in
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
             let new_nrows = Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 keep in
             let new_columns = List.map (fun (name, col) ->
               let new_col = Array.init new_nrows (fun j ->
                 let rec find_nth src_idx count =
                   if keep.(src_idx) then
                     (if count = j then col.(src_idx)
                      else find_nth (src_idx + 1) (count + 1))
                   else find_nth (src_idx + 1) count
                 in
                 find_nth 0 0
               ) in
               (name, new_col)
             ) df.columns in
             VDataFrame { columns = new_columns; nrows = new_nrows; group_keys = df.group_keys })
      | [VDataFrame _] -> make_error ArityError "filter() requires a DataFrame and a predicate function"
      | [_; _] -> make_error TypeError "filter() expects a DataFrame as first argument"
      | _ -> make_error ArityError "filter() takes exactly 2 arguments"
    ))
    env
