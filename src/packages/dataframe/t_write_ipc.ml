(* src/packages/to_dataframe/t_write_ipc.ml *)
open Ast

(*
--# Write Arrow IPC file
--#
--# Writes a DataFrame to an Apache Arrow IPC (Feather v2) file.
--#
--# IPC is the fastest format to read and write (no compression), ideal for
--# pipeline intermediates and cross-runtime exchange. For compressed,
--# long-term storage of large datasets, use write_parquet instead.
--#
--# @name write_ipc
--# @param df :: DataFrame The DataFrame to write.
--# @param path :: String The output file path.
--# @return :: Null
--# @example
--#   write_ipc(df, "data.arrow")
--# @family to_dataframe
--# @seealso read_ipc
--# @export
*)
let write_ipc_builtin =
  make_builtin ~name:"write_ipc" 2 (fun args _env ->
    match args with
    | [VDataFrame df; VString path] ->
        (match Arrow_io.write_ipc df.arrow_table path with
        | Ok () -> (VNA NAGeneric)
        | Error msg -> Error.make_error FileError (Printf.sprintf "File Error: %s." msg))
    | [v; VString _] ->
        let type_name = Utils.type_name v in
        let detail = match v with 
          | VError e -> Printf.sprintf " (Error: %s)" e.message
          | _ -> ""
        in
        Error.type_error ~arg_index:1
          (Printf.sprintf "Function `write_ipc` expects a DataFrame as first argument, got %s instead%s." type_name detail)
    | [VDataFrame _; v] ->
        Error.type_error ~arg_index:2
          (Printf.sprintf "Function `write_ipc` expects a String path as second argument, got %s instead." (Utils.type_name v))
    | [v1; v2] ->
        Error.type_error
          (Printf.sprintf "Function `write_ipc` expects (DataFrame, String), got (%s, %s) instead."
            (Utils.type_name v1) (Utils.type_name v2))
    | _ -> Error.arity_error_named "write_ipc" 2 (List.length args)
  )

let register env =
  Serialization_registry.update_native "ipc" ~writer:write_ipc_builtin ();
  Env.add "write_ipc" write_ipc_builtin env
