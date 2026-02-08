open Ast

let register env =
  Env.add "error"
    (make_builtin ~variadic:true 1 (fun args _env ->
      match args with
      | [VString msg] -> make_error GenericError msg
      | [VString code_str; VString msg] ->
          let code = match code_str with
            | "TypeError" -> TypeError
            | "ArityError" -> ArityError
            | "NameError" -> NameError
            | "DivisionByZero" -> DivisionByZero
            | "KeyError" -> KeyError
            | "IndexError" -> IndexError
            | "AssertionError" -> AssertionError
            | "FileError" -> FileError
            | "ValueError" -> ValueError
            | _ -> GenericError
          in
          make_error code msg
      | _ -> make_error ArityError "error() takes 1 or 2 string arguments"
    ))
    env
