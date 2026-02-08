open Ast

let register env =
  Env.add "abs"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VInt n] -> VInt (Int.abs n)
      | [VFloat f] -> VFloat (Float.abs f)
      | [VVector arr] ->
          let result = Array.make (Array.length arr) VNull in
          let had_error = ref None in
          Array.iteri (fun i v ->
            if !had_error = None then
              match v with
              | VInt n -> result.(i) <- VInt (Int.abs n)
              | VFloat f -> result.(i) <- VFloat (Float.abs f)
              | VNA _ -> had_error := Some (make_error TypeError "abs() encountered NA value. Handle missingness explicitly.")
              | _ -> had_error := Some (make_error TypeError "abs() requires numeric values")
          ) arr;
          (match !had_error with Some e -> e | None -> VVector result)
      | [VNA _] -> make_error TypeError "abs() encountered NA value. Handle missingness explicitly."
      | [_] -> make_error TypeError "abs() expects a number or numeric Vector"
      | _ -> make_error ArityError "abs() takes exactly 1 argument"
    ))
    env
