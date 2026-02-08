open Ast

let register ~make_builtin ~make_error env =
  Env.add "intent_fields"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VIntent { intent_fields }] ->
          VDict (List.map (fun (k, v) -> (k, VString v)) intent_fields)
      | [_] -> make_error TypeError "intent_fields() expects an Intent value"
      | _ -> make_error ArityError "intent_fields() takes exactly 1 argument"
    ))
    env
