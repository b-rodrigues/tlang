(* src/packages/to_dataframe/t_write_arrow.ml *)
open Ast

let register env =
  (*
  --# Write Arrow IPC file
  --#
  --# Writes a DataFrame to an Apache Arrow IPC (Feather v2) file.
  --#
  --# @name write_arrow
  --# @param df :: DataFrame The DataFrame to write.
  --# @param path :: String The output file path.
  --# @return :: Null
  --# @example
  --#   write_arrow(df, "data.arrow")
  --# @family to_dataframe
  --# @seealso read_arrow
  --# @export
  *)
  Env.add "write_arrow"
    (make_builtin ~name:"write_arrow" 2 (fun args _env ->
      match args with
      | [VDataFrame df; VString path] ->
          (match Arrow_io.write_ipc df.arrow_table path with
          | Ok () -> (VNA NAGeneric)
          | Error msg -> Error.make_error FileError (Printf.sprintf "File Error: %s." msg))
      | [v; VString _] ->
          Error.type_error ~arg_index:1
            (Printf.sprintf "Function `write_arrow` expects a DataFrame as first argument, got %s instead." (Utils.type_name v))
      | [VDataFrame _; v] ->
          Error.type_error ~arg_index:2
            (Printf.sprintf "Function `write_arrow` expects a String path as second argument, got %s instead." (Utils.type_name v))
      | [v1; v2] ->
          Error.type_error
            (Printf.sprintf "Function `write_arrow` expects (DataFrame, String), got (%s, %s) instead."
              (Utils.type_name v1) (Utils.type_name v2))
      | _ -> Error.arity_error_named "write_arrow" 2 (List.length args)
    ))
    env
