open Ast

let register env =
  Env.add "nrow"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { arrow_table; _ }] -> VInt (Arrow_table.num_rows arrow_table)
      | [VNA _] -> make_error TypeError "nrow() expects a DataFrame, got NA"
      | [_] -> make_error TypeError "nrow() expects a DataFrame"
      | _ -> make_error ArityError "nrow() takes exactly 1 argument"
    ))
    env
