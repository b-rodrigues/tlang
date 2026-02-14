open Ast

let register env =
  Env.add "length"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VList items] -> VInt (List.length items)
      | [VString s] -> VInt (String.length s)
      | [VDict pairs] -> VInt (List.length pairs)
      | [VVector arr] -> VInt (Array.length arr)
      | [VNA _] -> Error.type_error "Cannot get length of NA."
      | [VError _] -> Error.type_error "Cannot get length of Error."
      | [_] -> Error.type_error "Function `length` expects a List, String, Dict, or Vector."
      | _ -> Error.arity_error_named "length" ~expected:1 ~received:(List.length args)
    ))
    env
