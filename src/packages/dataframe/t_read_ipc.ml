(* src/packages/to_dataframe/t_read_ipc.ml *)
open Ast

(*
--# Read an Arrow IPC (Feather) file
--#
--# Loads a DataFrame from an Arrow IPC file (also known as Feather v2) on disk.
--#
--# IPC is the fastest format to read and write (no compression), ideal for
--# pipeline intermediates and cross-runtime exchange. For compressed,
--# long-term storage of large datasets, use read_parquet instead.
--#
--# @name read_ipc
--# @param path :: String The file path to the Arrow IPC file.
--# @return :: DataFrame The loaded DataFrame.
--# @example
--#   df = read_ipc("data.arrow")
--# @family to_dataframe
--# @seealso write_ipc, read_csv
--# @export
*)
let read_ipc_builtin =
  make_builtin ~name:"read_ipc" 1 (fun args _env ->
    match args with
    | [VString path] ->
        (match Arrow_io.read_ipc path with
        | Ok table -> VDataFrame { arrow_table = table; group_keys = [] }
        | Error msg -> Error.make_error FileError (Printf.sprintf "File Error: %s." msg))
    | [v] ->
        Error.type_error ~arg_index:1
          (Printf.sprintf "Function `read_ipc` expects a String path, got %s instead." (Utils.type_name v))
    | _ -> Error.arity_error_named "read_ipc" 1 (List.length args)
  )

let register env =
  Serialization_registry.update_native "ipc" ~reader:read_ipc_builtin ();
  Env.add "read_ipc" read_ipc_builtin env
