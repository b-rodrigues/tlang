open Ast

let register ~eval_call env =
  Env.add "map"
    (make_builtin 2 (fun args env ->
      match args with
      | [VList items; fn] ->
          let mapped = List.map (fun (name, v) ->
            let result = eval_call env fn [(None, Value v)] in
            (name, result)
          ) items in
          VList mapped
      | _ -> make_error TypeError "map() takes a List and a Function"
    ))
    env
