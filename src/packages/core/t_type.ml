open Ast

let register env =
  Env.add "type"
    (make_builtin 1 (fun args _env ->
      match args with
      | [v] -> VString (Utils.type_name v)
      | _ -> Error.arity_error_named "type" ~expected:1 ~received:(List.length args)
    ))
    env
