open Ast

(*
--# Read Parquet file
--#
--# Reads a DataFrame from a Parquet file using the native parquet-glib reader.
--#
--# @name read_parquet
--# @param path :: String Path or URL to the Parquet file.
--# @return :: DataFrame The loaded data.
--# @example
--#   df = read_parquet("data.parquet")
--# @family dataframe
--# @seealso read_csv, read_arrow
--# @export
*)
let register env =
  Env.add "read_parquet"
    (make_builtin ~name:"read_parquet" 1 (fun args _env ->
      match args with
      | [VString path] ->
          (match Arrow_io.read_parquet path with
          | Ok table -> VDataFrame { arrow_table = table; group_keys = [] }
          | Error msg -> Error.make_error FileError msg)
      | [VNA _] -> Error.type_error "Function `read_parquet` expects a String path, got NA."
      | [_] -> Error.type_error "Function `read_parquet` expects a String path."
      | _ -> Error.arity_error_named "read_parquet" 1 (List.length args)
    ))
    env
