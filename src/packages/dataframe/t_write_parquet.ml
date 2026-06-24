open Ast

(*
--# Write Parquet file
--#
--# Writes a DataFrame to a Parquet file using the native parquet-glib writer.
--#
--# @name write_parquet
--# @param df :: DataFrame The DataFrame to write.
--# @param path :: String The output file path.
--# @return :: Null
--# @example
--#   write_parquet(df, "data.parquet")
--# @family to_dataframe
--# @seealso read_parquet, write_arrow
--# @export
*)
let register env =
  Env.add "write_parquet"
    (make_builtin ~name:"write_parquet" 2 (fun args _env ->
      match args with
      | [VDataFrame df; VString path] ->
          (match Arrow_io.write_parquet df.arrow_table path with
          | Ok () -> (VNA NAGeneric)
          | Error msg -> Error.make_error FileError (Printf.sprintf "File Error: %s." msg))
      | [v; VString _] ->
          let type_name = Utils.type_name v in
          let detail = match v with 
            | VError e -> Printf.sprintf " (Error: %s)" e.message
            | _ -> ""
          in
          Error.type_error ~arg_index:1
            (Printf.sprintf "Function `write_parquet` expects a DataFrame as first argument, got %s instead%s." type_name detail)
      | [VDataFrame _; v] ->
          Error.type_error ~arg_index:2
            (Printf.sprintf "Function `write_parquet` expects a String path as second argument, got %s instead." (Utils.type_name v))
      | [v1; v2] ->
          Error.type_error
            (Printf.sprintf "Function `write_parquet` expects (DataFrame, String), got (%s, %s) instead."
              (Utils.type_name v1) (Utils.type_name v2))
      | _ -> Error.arity_error_named "write_parquet" 2 (List.length args)
    ))
    env
