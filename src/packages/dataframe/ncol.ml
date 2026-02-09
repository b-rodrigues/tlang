open Ast

let register env =
  Env.add "ncol"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { arrow_table; _ }] -> VInt (Arrow_table.num_columns arrow_table)
      | [VNA _] -> make_error TypeError "ncol() expects a DataFrame, got NA"
      | [_] -> make_error TypeError "ncol() expects a DataFrame"
      | _ -> make_error ArityError "ncol() takes exactly 1 argument"
    ))
    env
