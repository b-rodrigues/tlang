(* src/packages/dataframe/t_write_arrow.ml *)
open Ast

let register env =
  Env.add "write_arrow"
    (make_builtin ~name:"write_arrow" 2 (fun args _env ->
      match args with
      | [VDataFrame df; VString path] ->
          (match Arrow_io.write_ipc df.arrow_table path with
          | Ok () -> VNull
          | Error msg -> Error.make_error FileError (Printf.sprintf "File Error: %s." msg))
      | [_; VString _] -> Error.type_error "Function `write_arrow` expects a DataFrame as first argument."
      | [VDataFrame _; _] -> Error.type_error "Function `write_arrow` expects a String path as second argument."
      | [_; _] -> Error.type_error "Function `write_arrow` expects (DataFrame, String)."
      | _ -> Error.arity_error_named "write_arrow" ~expected:2 ~received:(List.length args)
    ))
    env
