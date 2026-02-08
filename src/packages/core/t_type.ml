open Ast

let register env =
  Env.add "type"
    (make_builtin 1 (fun args _env ->
      match args with
      | [v] -> VString (Utils.type_name v)
      | _ -> make_error ArityError "type() takes exactly 1 argument"
    ))
    env
