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
--# @family dataframe
--# @seealso read_csv
--# @export
*)
let register ~write_csv_fn env =
  Env.add "write_csv"
    (make_builtin_named ~variadic:true 2 (fun named_args _env ->
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
          | Ok () -> VNull
          | Error msg -> Error.make_error FileError (Printf.sprintf "File Error: %s." msg))
      | [_; VString _] -> Error.type_error "Function `write_csv` expects a DataFrame as first argument."
      | [VDataFrame _; _] -> Error.type_error "Function `write_csv` expects a String path as second argument."
      | _ -> Error.make_error ArityError "Function `write_csv` takes exactly 2 positional arguments (dataframe, path)."
    ))
    env
