open Ast

let register env =
  Env.add "intent_fields"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VIntent { intent_fields }] ->
          VDict (List.map (fun (k, v) -> (k, VString v)) intent_fields)
      | [_] -> Error.type_error "Function `intent_fields` expects an Intent value."
      | _ -> Error.arity_error_named "intent_fields" ~expected:1 ~received:(List.length args)
    ))
    env
