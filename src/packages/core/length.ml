open Ast

let register env =
  Env.add "length"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VList items] -> VInt (List.length items)
      | [VString s] -> VInt (String.length s)
      | [VDict pairs] -> VInt (List.length pairs)
      | [VVector arr] -> VInt (Array.length arr)
      | [VNA _] -> make_error TypeError "Cannot get length of NA"
      | [VError _] -> make_error TypeError "Cannot get length of Error"
      | [_] -> make_error TypeError "length() expects a List, String, Dict, or Vector"
      | _ -> make_error ArityError "length() takes exactly 1 argument"
    ))
    env
