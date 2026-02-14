open Ast

let register env =
  Env.add "nrow"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDataFrame { arrow_table; _ }] -> VInt (Arrow_table.num_rows arrow_table)
      | [VVector v] -> VInt (Array.length v)
      | [VNA _] -> Error.type_error "Function `nrow` expects a DataFrame or vector, got NA."
      | [_] -> Error.type_error "Function `nrow` expects a DataFrame or vector."
      | _ -> Error.arity_error_named "nrow" ~expected:1 ~received:(List.length args)
    ))
    env
