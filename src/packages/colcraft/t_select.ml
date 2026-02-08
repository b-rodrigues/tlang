open Ast

let register ~make_builtin ~make_error env =
  Env.add "select"
    (make_builtin ~variadic:true 1 (fun args _env ->
      match args with
      | VDataFrame df :: col_args ->
          let col_names = List.map (fun v ->
            match v with
            | VString s -> Ok s
            | _ -> Error (make_error TypeError "select() expects string column names")
          ) col_args in
          (match List.find_opt Result.is_error col_names with
           | Some (Error e) -> e
           | _ ->
             let names = List.map (fun r -> match r with Ok s -> s | _ -> "") col_names in
             let missing = List.filter (fun n -> not (List.mem_assoc n df.columns)) names in
             if missing <> [] then
               make_error KeyError (Printf.sprintf "Column(s) not found: %s" (String.concat ", " missing))
             else
               let selected = List.map (fun n -> (n, List.assoc n df.columns)) names in
               let remaining_keys = List.filter (fun k -> List.mem k names) df.group_keys in
               VDataFrame { columns = selected; nrows = df.nrows; group_keys = remaining_keys })
      | _ :: _ -> make_error TypeError "select() expects a DataFrame as first argument"
      | _ -> make_error ArityError "select() requires a DataFrame and at least one column name"
    ))
    env
