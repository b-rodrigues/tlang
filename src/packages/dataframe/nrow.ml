open Ast

let register env =
  Env.add "nrow"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { arrow_table; _ }] -> VInt (Arrow_table.num_rows arrow_table)
      | [VVector v] -> VInt (Array.length v)
      | [VNA _] -> make_error TypeError "nrow() expects a DataFrame or vector, got NA"
      | [_] -> make_error TypeError "nrow() expects a DataFrame or vector"
      | _ -> make_error ArityError "nrow() takes exactly 1 argument"
    ))
    env
