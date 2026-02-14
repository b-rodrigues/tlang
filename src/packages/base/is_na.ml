open Ast

let register env =
  Env.add "is_na"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VNA _] -> VBool true
      | [_] -> VBool false
      | _ -> Error.arity_error_named "is_na" ~expected:1 ~received:(List.length args)
    ))
    env
