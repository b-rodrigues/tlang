open Ast

let register env =
  Env.add "iota"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VInt n] ->
          if n < 0 then Error.value_error "iota expects a non-negative integer."
          else
            let arr = Array.make n (VFloat 1.0) in
            VVector arr
      | _ -> Error.type_error "iota expects a single Integer argument."
    ))
    env
