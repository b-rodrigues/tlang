(* src/packages/dataframe/t_read_arrow.ml *)
open Ast

let read_arrow_builtin =
  make_builtin ~name:"read_arrow" 1 (fun args _env ->
    match args with
    | [VString path] ->
        (match Arrow_io.read_ipc path with
        | Ok table -> VDataFrame { arrow_table = table; group_keys = [] }
        | Error msg -> Error.make_error FileError (Printf.sprintf "File Error: %s." msg))
    | [VNA _] -> Error.type_error "Function `read_arrow` expects a String path, got NA."
    | [_] -> Error.type_error "Function `read_arrow` expects a String path."
    | _ -> Error.arity_error_named "read_arrow" 1 (List.length args)
  )

let register env =
  Serialization_registry.update_native "arrow" ~reader:read_arrow_builtin ();
  Env.add "read_arrow" read_arrow_builtin env
