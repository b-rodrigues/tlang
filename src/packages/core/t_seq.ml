open Ast

let register ~make_builtin ~make_error env =
  Env.add "seq"
    (make_builtin 2 (fun args _env ->
      match args with
      | [VInt a; VInt b] ->
          let items = List.init (b - a + 1) (fun i -> (None, VInt (a + i))) in
          VList items
      | _ -> make_error TypeError "seq() takes exactly 2 Int arguments"
    ))
    env
