(* src/packages/dataframe/t_read_arrow.ml *)
open Ast

let register env =
  Env.add "t_read_arrow"
    (make_builtin ~name:"t_read_arrow" 1 (fun args _env ->
      match args with
      | [VString path] ->
          (match Arrow_io.read_ipc path with
          | Ok table -> VDataFrame { arrow_table = table; group_keys = [] }
          | Error msg -> Error.make_error FileError (Printf.sprintf "File Error: %s." msg))
      | [VNA _] -> Error.type_error "Function `t_read_arrow` expects a String path, got NA."
      | [_] -> Error.type_error "Function `t_read_arrow` expects a String path."
      | _ -> Error.arity_error_named "t_read_arrow" ~expected:1 ~received:(List.length args)
    ))
    env
