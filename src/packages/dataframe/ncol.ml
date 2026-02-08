open Ast

let register ~make_builtin ~make_error env =
  Env.add "ncol"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { columns; _ }] -> VInt (List.length columns)
      | [VNA _] -> make_error TypeError "ncol() expects a DataFrame, got NA"
      | [_] -> make_error TypeError "ncol() expects a DataFrame"
      | _ -> make_error ArityError "ncol() takes exactly 1 argument"
    ))
    env
