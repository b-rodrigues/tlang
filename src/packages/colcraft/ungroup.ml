open Ast

let register env =
  Env.add "ungroup"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame df] ->
          VDataFrame { df with group_keys = [] }
      | [_] -> make_error TypeError "ungroup() expects a DataFrame as first argument"
      | _ -> make_error ArityError "ungroup() takes exactly 1 argument"
    ))
    env
