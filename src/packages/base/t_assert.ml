open Ast

let register ~make_builtin ~make_error ~is_na_value env =
  Env.add "assert"
    (make_builtin ~variadic:true 1 (fun args _env ->
      match args with
      | [v] ->
          if is_na_value v then
            make_error AssertionError "Assertion received NA"
          else if Utils.is_truthy v then VBool true
          else make_error AssertionError "Assertion failed"
      | [v; VString msg] ->
          if is_na_value v then
            make_error AssertionError ("Assertion received NA: " ^ msg)
          else if Utils.is_truthy v then VBool true
          else make_error AssertionError ("Assertion failed: " ^ msg)
      | _ -> make_error ArityError "assert() takes 1 or 2 arguments"
    ))
    env
