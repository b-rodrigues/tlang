open Ast

let register env =
  Env.add "colnames"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { arrow_table; _ }] ->
          VList (List.map (fun name -> (None, VString name)) (Arrow_table.column_names arrow_table))
      | [VNA _] -> make_error TypeError "colnames() expects a DataFrame, got NA"
      | [_] -> make_error TypeError "colnames() expects a DataFrame"
      | _ -> make_error ArityError "colnames() takes exactly 1 argument"
    ))
    env
