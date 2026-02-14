open Ast

let register env =
  Env.add "ungroup"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame df] ->
          VDataFrame { df with group_keys = [] }
      | [_] -> Error.type_error "Function `ungroup` expects a DataFrame as first argument."
      | _ -> Error.make_error ArityError "Function `ungroup` takes exactly 1 argument."
    ))
    env
