open Ast

let register env =
  Env.add "tail"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VList []] -> make_error ValueError "tail() called on empty list"
      | [VList (_ :: rest)] -> VList rest
      | [VNA _] -> make_error TypeError "Cannot call tail() on NA"
      | [_] -> make_error TypeError "tail() expects a List"
      | _ -> make_error ArityError "tail() takes exactly 1 argument"
    ))
    env
