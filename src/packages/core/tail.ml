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
      | [VList []] -> Error.value_error "Function `tail` called on empty List."
      | [VList (_ :: rest)] -> VList rest
      | [VVector arr] when Array.length arr > 0 ->
          VVector (Array.sub arr 1 (Array.length arr - 1))
      | [VVector _] -> Error.value_error "Function `tail` called on empty Vector."
      | [VNA _] -> Error.type_error "Function `tail` cannot be called on NA."
      | [_] -> Error.type_error "Function `tail` expects a DataFrame or List."
      | _ -> Error.arity_error_named "tail" ~expected:1 ~received:(List.length args)
    ))
    env
