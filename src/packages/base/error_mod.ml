open Ast

(*
--# Raise Error
--#
--# Raises a runtime error with a message and optional code.
--#
--# @name error
--# @param message :: String The error message.
--# @param code :: String (Optional) Error code (e.g., "ValueError").
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
    (make_builtin ~variadic:true 1 (fun args _env ->
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
            | _ -> GenericError
          in
          Error.make_error code msg
      | _ -> Error.make_error ArityError (Printf.sprintf "Function `error` expects 1 or 2 string arguments but received %d." (List.length args))
    ))
    env
