open Ast

(*
--# Select columns
--#
--# Selects specific columns from a DataFrame.
--#
--# @name select
--# @param df :: DataFrame The input DataFrame.
--# @param ... :: Symbol Variable number of column names (e.g., $col1, $col2).
--# @return :: DataFrame The DataFrame with selected columns.
--# @example
--#   select(mtcars, $mpg, $wt)
--# @family colcraft
--# @seealso filter, mutate
--# @export
*)
let register env =
  Env.add "select"
    (make_builtin ~name:"select" ~variadic:true 1 (fun args _env ->
      match args with
      | VDataFrame df :: col_args ->
          let process_col v =
            match v with
            | VSymbol _ ->
                (match Utils.extract_column_name v with
                 | Some s -> Ok [s]
                 | None -> Error (Error.type_error "Function `select` invalid symbol."))
            | VString s -> Ok [s]
            | VList items ->
                let names = List.map (fun (_, v) -> match v with VString s -> Ok s | _ -> Error (Error.type_error "List in `select` must contain strings.")) items in
                (match List.find_opt Result.is_error names with
                 | Some (Error e) -> Error e
                 | _ -> Ok (List.map (fun r -> match r with Ok s -> s | _ -> "") names))
            | VBuiltin b ->
                (* Special Case: Selection Helper Matcher *)
                (match b.b_func [(None, VDataFrame df)] (ref Env.empty) with
                 | VList items -> 
                     let names = List.map (fun (_, v) -> match v with VString s -> Ok s | _ -> Error (Error.type_error "Matcher must return list of strings.")) items in
                     (match List.find_opt Result.is_error names with
                      | Some (Error e) -> Error e
                      | _ -> Ok (List.map (fun r -> match r with Ok s -> s | _ -> "") names))
                 | other -> Error (Error.type_error ("Matcher returned " ^ Utils.value_to_string other)))
            | _ -> Error (Error.type_error "Function `select` expects $column syntax.")
          in
          let all_names_results = List.map process_col col_args in
          (match List.find_opt (fun r -> match r with Error _ -> true | _ -> false) all_names_results with
           | Some (Error e) -> e
           | _ ->
             let names = List.concat_map (fun r -> match r with Ok ns -> ns | _ -> []) all_names_results in
             let missing = List.filter (fun n -> not (Arrow_table.has_column df.arrow_table n)) names in
             if missing <> [] then
               Error.make_error KeyError (Printf.sprintf "Column(s) not found: %s." (String.concat ", " missing))
             else
               let new_table = Arrow_compute.project df.arrow_table names in
               let remaining_keys = List.filter (fun k -> List.mem k names) df.group_keys in
               VDataFrame { arrow_table = new_table; group_keys = remaining_keys })
      | _ :: _ -> Error.type_error "Function `select` expects a DataFrame as first argument."
      | _ -> Error.make_error ArityError "Function `select` requires a DataFrame and at least one $column."
    ))
    env

