open Ast

let register ~make_builtin ~make_error env =
  Env.add "head"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VList []] -> make_error ValueError "head() called on empty list"
      | [VList ((_, v) :: _)] -> v
      | [VNA _] -> make_error TypeError "Cannot call head() on NA"
      | [_] -> make_error TypeError "head() expects a List"
      | _ -> make_error ArityError "head() takes exactly 1 argument"
    ))
    env
