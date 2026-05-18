open Ast

let is_sep_name = function Some "separator" -> true | _ -> false

(*
--# Write CSV file
--#
--# Writes a DataFrame to a CSV file.
--#
--# @name write_csv
--# @param df :: DataFrame The data to write.
--# @param path :: String The output path.
--# @param separator :: String (Optional) Field separator (default ",").
--# @return :: Null
--# @example
--#   write_csv(df, "output.csv")
--# @family to_dataframe
--# @seealso read_csv
--# @export
*)
let register ~write_csv_fn env =
  Env.add "write_csv"
    (make_builtin_named ~name:"write_csv" ~variadic:true 2 (fun named_args _env ->
      (* Extract named arguments *)
      let sep = List.fold_left (fun acc (name, v) ->
        match name, v with
        | n, VString s when is_sep_name n -> s
        | _ -> acc
      ) "," named_args in
      (* Extract positional arguments *)
      let args = List.filter (fun (name, _) ->
        not (is_sep_name name)
      ) named_args |> List.map snd in
      match args with
      | [VDataFrame df; VString path] ->
          (match write_csv_fn ~sep df.arrow_table path with
          | Ok () -> (VNA NAGeneric)
          | Error msg -> Error.make_error FileError (Printf.sprintf "File Error: %s." msg))
      | [v; VString _] ->
          Error.type_error ~arg_index:1
            (Printf.sprintf "Function `write_csv` expects a DataFrame as first argument, got %s instead." (Utils.type_name v))
      | [VDataFrame _; v] ->
          Error.type_error ~arg_index:2
            (Printf.sprintf "Function `write_csv` expects a String path as second argument, got %s instead." (Utils.type_name v))
      | [v1; v2] ->
          Error.type_error
            (Printf.sprintf "Function `write_csv` expects (DataFrame, String), got (%s, %s) instead."
              (Utils.type_name v1) (Utils.type_name v2))
      | _ -> Error.arity_error_named "write_csv" 2 (List.length args)
    ))
    env
