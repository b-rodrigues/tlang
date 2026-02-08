open Ast

let register ~make_builtin ~make_error env =
  let env = Env.add "error_code"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VError { code; _ }] -> VString (Utils.error_code_to_string code)
      | [_] -> make_error TypeError "error_code() expects an Error value"
      | _ -> make_error ArityError "error_code() takes exactly 1 argument"
    ))
    env in
  let env = Env.add "error_message"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VError { message; _ }] -> VString message
      | [_] -> make_error TypeError "error_message() expects an Error value"
      | _ -> make_error ArityError "error_message() takes exactly 1 argument"
    ))
    env in
  let env = Env.add "error_context"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VError { context; _ }] ->
          VDict context
      | [_] -> make_error TypeError "error_context() expects an Error value"
      | _ -> make_error ArityError "error_context() takes exactly 1 argument"
    ))
    env in
  env
