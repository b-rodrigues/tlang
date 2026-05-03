open Ast

(*
--# Raise Error
--#
--# Raises a runtime error with a message and optional code.
--#
--# @name error
--# @param message_or_code :: String The error message (if 1 argument) or error code (if 2 arguments).
--# @param message :: String (Optional) The error message if a code was provided as the first argument.
--# @return :: Error
--# @example
--#   error("Invalid input")
--#   error("ValueError", "Must be positive")
--# @family base
--# @seealso assert, is_error
--# @export
*)
let register env =
  Env.add "error"
    (make_builtin ~name:"error" ~variadic:true 1 (fun args _env ->
      match args with
      | [VString msg] -> Error.make_error GenericError msg
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
            | "SyntaxError" -> SyntaxError
            | "ShellError" -> ShellError
            | "RuntimeError" -> RuntimeError
            | "StructuralError" -> StructuralError
            | _ -> GenericError
          in
          Error.make_error code msg
      | [_] -> Error.type_error "Function `error` expects a String message."
      | [_; _] -> Error.type_error "Function `error` expects (String code, String message)."
      | _ -> Error.make_error ArityError (Printf.sprintf "Function `error` expects 1 or 2 string arguments but received %d." (List.length args))
    ))
    env
