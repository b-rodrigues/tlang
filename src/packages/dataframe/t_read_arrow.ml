(* src/packages/to_dataframe/t_read_arrow.ml *)
open Ast

(*
--# Read an Arrow IPC (Feather) file
--#
--# Loads a DataFrame from an Arrow IPC file (also known as Feather v2) on disk.
--#
--# @name read_arrow
--# @param path :: String The file path to the Arrow IPC file.
--# @return :: DataFrame The loaded DataFrame.
--# @example
--#   df = read_arrow("data.arrow")
--# @family to_dataframe
--# @seealso write_arrow, read_csv
--# @export
*)
let read_arrow_builtin =
  make_builtin ~name:"read_arrow" 1 (fun args _env ->
    match args with
    | [VString path] ->
        (match Arrow_io.read_ipc path with
        | Ok table -> VDataFrame { arrow_table = table; group_keys = [] }
        | Error msg -> Error.make_error FileError (Printf.sprintf "File Error: %s." msg))
    | [v] ->
        Error.type_error ~arg_index:1
          (Printf.sprintf "Function `read_arrow` expects a String path, got %s instead." (Utils.type_name v))
    | _ -> Error.arity_error_named "read_arrow" 1 (List.length args)
  )

let register env =
  Serialization_registry.update_native "arrow" ~reader:read_arrow_builtin ();
  Env.add "read_arrow" read_arrow_builtin env
