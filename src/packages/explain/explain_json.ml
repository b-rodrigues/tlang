open Ast

let register ~make_builtin ~make_error ~eval_call env =
  Env.add "explain_json"
    (make_builtin 1 (fun args env ->
      match args with
      | [v] ->
          (match Env.find_opt "explain" env with
           | Some explain_fn ->
               let explain_result = eval_call env explain_fn [(None, Value v)] in
               (match explain_result with
                | VError _ -> explain_result
                | _ -> VString (Utils.value_to_string explain_result))
           | None -> make_error GenericError "explain_json(): explain function not found in environment")
      | _ -> make_error ArityError "explain_json() takes exactly 1 argument"
    ))
    env
