open Ast

let register ~make_builtin ~make_error env =
  Env.add "group_by"
    (make_builtin ~variadic:true 1 (fun args _env ->
      match args with
      | VDataFrame df :: key_args ->
          let key_names = List.map (fun v ->
            match v with
            | VString s -> Ok s
            | _ -> Error (make_error TypeError "group_by() expects string column names")
          ) key_args in
          (match List.find_opt Result.is_error key_names with
           | Some (Error e) -> e
           | _ ->
             let names = List.map (fun r -> match r with Ok s -> s | _ -> "") key_names in
             let missing = List.filter (fun n -> not (List.mem_assoc n df.columns)) names in
             if missing <> [] then
               make_error KeyError (Printf.sprintf "Column(s) not found: %s" (String.concat ", " missing))
             else if names = [] then
               make_error ArityError "group_by() requires at least one column name"
             else
               VDataFrame { df with group_keys = names })
      | [_] -> make_error TypeError "group_by() expects a DataFrame as first argument"
      | _ -> make_error ArityError "group_by() requires a DataFrame and at least one column name"
    ))
    env
