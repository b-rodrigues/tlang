open Ast

let register ~write_csv_fn env =
  Env.add "write_csv"
    (make_builtin 2 (fun args _env ->
      match args with
      | [VDataFrame df; VString path] ->
          (match write_csv_fn df.arrow_table path with
          | Ok () -> VNull
          | Error msg -> make_error FileError msg)
      | [_; VString _] -> make_error TypeError "write_csv() expects a DataFrame as first argument"
      | [VDataFrame _; _] -> make_error TypeError "write_csv() expects a String path as second argument"
      | _ -> make_error ArityError "write_csv() takes exactly 2 arguments (dataframe, path)"
    ))
    env
