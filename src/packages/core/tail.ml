open Ast

let register env =
  Env.add "tail"
    (make_builtin_named ~variadic:true 1 (fun named_args _env ->
      (* Extract named arguments *)
      let n_named = List.fold_left (fun acc (name, v) ->
        match name, v with
        | Some "n", VInt n when n >= 0 -> Some n
        | _ -> acc
      ) None named_args in
      (* Extract positional arguments *)
      let args = List.filter (fun (name, _) ->
        name <> Some "n"
      ) named_args |> List.map snd in
      let take_tail_df arrow_table group_keys n =
        let nrows = Arrow_table.num_rows arrow_table in
        let take_n = min n nrows in
        let start = nrows - take_n in
        let indices = List.init take_n (fun i -> start + i) in
        let new_table = Arrow_table.take_rows arrow_table indices in
        VDataFrame { arrow_table = new_table; group_keys }
      in
      match args with
      | [VDataFrame { arrow_table; group_keys }] ->
          let n = match n_named with Some n -> n | None -> 5 in
          take_tail_df arrow_table group_keys n
      | [VDataFrame { arrow_table; group_keys }; VInt n] when n >= 0 ->
          take_tail_df arrow_table group_keys n
      | [VList []] -> make_error ValueError "tail() called on empty list"
      | [VList (_ :: rest)] -> VList rest
      | [VNA _] -> make_error TypeError "Cannot call tail() on NA"
      | [_] -> make_error TypeError "tail() expects a DataFrame or List"
      | _ -> make_error ArityError "tail() takes 1 or 2 arguments (collection, n)"
    ))
    env
