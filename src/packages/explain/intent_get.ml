open Ast

let register env =
  Env.add "intent_get"
    (make_builtin 2 (fun args _env ->
      match args with
      | [VIntent { intent_fields }; VString key] ->
          (match List.assoc_opt key intent_fields with
           | Some v -> VString v
           | None -> Error.make_error KeyError (Printf.sprintf "Intent field `%s` not found." key))
      | [VIntent _; _] -> Error.type_error "Function `intent_get` expects a String key as second argument."
      | [_; _] -> Error.type_error "Function `intent_get` expects an Intent value as first argument."
      | _ -> Error.arity_error_named "intent_get" ~expected:2 ~received:(List.length args)
    ))
    env
