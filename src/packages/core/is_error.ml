open Ast

let register ~make_builtin ~make_error env =
  Env.add "is_error"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VError _] -> VBool true
      | [_] -> VBool false
      | _ -> make_error ArityError "is_error() takes exactly 1 argument"
    ))
    env
