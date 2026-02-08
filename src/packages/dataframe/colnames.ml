open Ast

let register env =
  Env.add "colnames"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { columns; _ }] ->
          VList (List.map (fun (name, _) -> (None, VString name)) columns)
      | [VNA _] -> make_error TypeError "colnames() expects a DataFrame, got NA"
      | [_] -> make_error TypeError "colnames() expects a DataFrame"
      | _ -> make_error ArityError "colnames() takes exactly 1 argument"
    ))
    env
