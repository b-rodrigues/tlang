open Ast

let register env =
  Env.add "colnames"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { arrow_table; _ }] ->
          VList (List.map (fun name -> (None, VString name)) (Arrow_table.column_names arrow_table))
      | [VNA _] -> Error.type_error "Function `colnames` expects a DataFrame, got NA."
      | [_] -> Error.type_error "Function `colnames` expects a DataFrame."
      | _ -> Error.arity_error_named "colnames" ~expected:1 ~received:(List.length args)
    ))
    env
