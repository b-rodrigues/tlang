open Ast

let register ~make_builtin ~make_error env =
  Env.add "nrow"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { nrows; _ }] -> VInt nrows
      | [VNA _] -> make_error TypeError "nrow() expects a DataFrame, got NA"
      | [_] -> make_error TypeError "nrow() expects a DataFrame"
      | _ -> make_error ArityError "nrow() takes exactly 1 argument"
    ))
    env
