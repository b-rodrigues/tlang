open Ast

let register ~write_csv_fn env =
  Env.add "write_csv"
    (make_builtin_named ~variadic:true 2 (fun named_args _env ->
      (* Extract named arguments *)
      let sep = List.fold_left (fun acc (name, v) ->
        match name, v with
        | Some "sep", VString s -> s
        | _ -> acc
      ) "," named_args in
      (* Extract positional arguments *)
      let args = List.filter (fun (name, _) ->
        name <> Some "sep"
      ) named_args |> List.map snd in
      match args with
      | [VDataFrame df; VString path] ->
          (match write_csv_fn ~sep df.arrow_table path with
          | Ok () -> VNull
          | Error msg -> make_error FileError msg)
      | [_; VString _] -> make_error TypeError "write_csv() expects a DataFrame as first argument"
      | [VDataFrame _; _] -> make_error TypeError "write_csv() expects a String path as second argument"
      | _ -> make_error ArityError "write_csv() takes exactly 2 positional arguments (dataframe, path)"
    ))
    env
