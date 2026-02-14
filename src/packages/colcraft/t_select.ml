open Ast

let register env =
  Env.add "select"
    (make_builtin ~variadic:true 1 (fun args _env ->
      match args with
      | VDataFrame df :: col_args ->
          let col_names = List.map (fun v ->
            match Utils.extract_column_name v with
            | Some s -> Ok s
            | None -> Error (Error.type_error "Function `select` expects $column syntax.")
          ) col_args in
          (match List.find_opt Result.is_error col_names with
           | Some (Error e) -> e
           | _ ->
             let names = List.map (fun r -> match r with Ok s -> s | _ -> "") col_names in
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

