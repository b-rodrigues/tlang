open Ast

let register env =
  Env.add "is_na"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VNA _] -> VBool true
      | [_] -> VBool false
      | _ -> make_error ArityError "is_na() takes exactly 1 argument"
    ))
    env
