open Ast

(*
--# Get error code
--#
--# Returns the error code as a string (e.g., "TypeError", "ValueError").
--#
--# @name error_code
--# @param x :: Error The error value to inspect.
--# @return :: String The error code as a string.
--# @family base
--# @export
*)
let register env =
  let env = Env.add "error_code"
    (make_builtin ~name:"error_code" 1 (fun args _env ->
      match args with
      | [VError { code; _ }] -> VString (Utils.error_code_to_string code)
      | [_] -> Error.type_error "Function `error_code` expects an Error value."
      | _ -> Error.arity_error_named "error_code" ~expected:1 ~received:(List.length args)
    ))
    env in
  
  (*
  --# Get error message
  --#
  --# Returns the human-readable message associated with an error.
  --#
  --# @name error_message
  --# @param x :: Error The error value to inspect.
  --# @return :: String The error message.
  --# @family base
  --# @export
  *)
  let env = Env.add "error_message"
    (make_builtin ~name:"error_message" 1 (fun args _env ->
      match args with
      | [VError { message; _ }] -> VString message
      | [_] -> Error.type_error "Function `error_message` expects an Error value."
      | _ -> Error.arity_error_named "error_message" ~expected:1 ~received:(List.length args)
    ))
    env in
  
  (*
  --# Get error context
  --#
  --# Returns a dictionary containing contextual information about where and why
  --# the error occurred.
  --#
  --# @name error_context
  --# @param x :: Error The error value to inspect.
  --# @return :: Dict A dictionary of related context data.
  --# @family base
  --# @export
  *)
  let env = Env.add "error_context"
    (make_builtin ~name:"error_context" 1 (fun args _env ->
      match args with
      | [VError { context; _ }] ->
          VDict context
      | [_] -> Error.type_error "Function `error_context` expects an Error value."
      | _ -> Error.arity_error_named "error_context" ~expected:1 ~received:(List.length args)
    ))
    env in
  env
