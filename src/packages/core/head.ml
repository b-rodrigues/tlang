open Ast

let register env =
  Env.add "head"
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
      let take_head_df arrow_table group_keys n =
        let nrows = Arrow_table.num_rows arrow_table in
        let take_n = min n nrows in
        let indices = List.init take_n (fun i -> i) in
        let new_table = Arrow_table.take_rows arrow_table indices in
        VDataFrame { arrow_table = new_table; group_keys }
      in
      match args with
      | [VDataFrame { arrow_table; group_keys }] ->
          let n = match n_named with Some n -> n | None -> 5 in
          take_head_df arrow_table group_keys n
      | [VDataFrame { arrow_table; group_keys }; VInt n] when n >= 0 ->
          take_head_df arrow_table group_keys n
      | [VList []] -> make_error ValueError "head() called on empty list"
      | [VList ((_, v) :: _)] -> v
      | [VVector arr] when Array.length arr > 0 -> arr.(0)
      | [VVector _] -> make_error ValueError "head() called on empty vector"
      | [VNA _] -> make_error TypeError "Cannot call head() on NA"
      | [_] -> make_error TypeError "head() expects a DataFrame or List"
      | _ -> make_error ArityError "head() takes 1 or 2 arguments (collection, n)"
    ))
    env
