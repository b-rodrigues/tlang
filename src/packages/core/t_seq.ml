open Ast

let register env =
  Env.add "seq"
    (make_builtin 2 (fun args _env ->
      match args with
      | [VInt a; VInt b] ->
          let items = List.init (b - a + 1) (fun i -> (None, VInt (a + i))) in
          VList items
      | _ -> Error.type_error "Function `seq` expects two Int arguments."
    ))
    env
