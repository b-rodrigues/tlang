open Ast

(*
--# Group by columns
--#
--# Groups a DataFrame by one or more columns for subsequent aggregation.
--#
--# @name group_by
--# @param df :: DataFrame The input DataFrame.
--# @param ... :: Symbol Variable number of grouping columns.
--# @return :: DataFrame The grouped DataFrame.
--# @example
--#   group_by(mtcars, $cyl)
--#   group_by(mtcars, $cyl, $gear)
--# @family colcraft
--# @seealso summarize, ungroup
--# @export
*)
let register env =
  Env.add "group_by"
    (make_builtin ~variadic:true 1 (fun args _env ->
      match args with
      | VDataFrame df :: key_args ->
          let key_names = List.map (fun v ->
            match Utils.extract_column_name v with
            | Some s -> Ok s
            | None -> Error (Error.type_error "Function `group_by` expects $column syntax.")
          ) key_args in
          (match List.find_opt Result.is_error key_names with
           | Some (Error e) -> e
           | _ ->
             let names = List.map (fun r -> match r with Ok s -> s | _ -> "") key_names in
             let missing = List.filter (fun n -> not (Arrow_table.has_column df.arrow_table n)) names in
             if missing <> [] then
               Error.make_error KeyError (Printf.sprintf "Column(s) not found: %s." (String.concat ", " missing))
             else if names = [] then
               Error.make_error ArityError "Function `group_by` requires at least one $column."
             else
               VDataFrame { df with group_keys = names })
      | [_] -> Error.type_error "Function `group_by` expects a DataFrame as first argument."
      | _ -> Error.make_error ArityError "Function `group_by` requires a DataFrame and at least one $column."
     ))
     env
