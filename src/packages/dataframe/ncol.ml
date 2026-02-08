open Ast

let register env =
  Env.add "ncol"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { columns; _ }] -> VInt (List.length columns)
      | [VNA _] -> make_error TypeError "ncol() expects a DataFrame, got NA"
      | [_] -> make_error TypeError "ncol() expects a DataFrame"
      | _ -> make_error ArityError "ncol() takes exactly 1 argument"
    ))
    env
