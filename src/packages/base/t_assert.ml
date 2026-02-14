open Ast

let register env =
  Env.add "assert"
    (make_builtin ~variadic:true 1 (fun args _env ->
      match args with
      | [v] ->
          if is_na_value v then
            Error.make_error AssertionError "Assertion received NA."
          else if Utils.is_truthy v then VBool true
          else Error.make_error AssertionError "Assertion failed."
      | [v; VString msg] ->
          if is_na_value v then
            Error.make_error AssertionError ("Assertion received NA: " ^ msg ^ ".")
          else if Utils.is_truthy v then VBool true
          else Error.make_error AssertionError ("Assertion failed: " ^ msg ^ ".")
      | _ -> Error.make_error ArityError (Printf.sprintf "Function `assert` expects 1 or 2 arguments but received %d." (List.length args))
    ))
    env
