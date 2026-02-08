open Ast

let register env =
  Env.add "sum"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VList items] ->
          let rec add_all = function
            | [] -> VInt 0
            | (_, VInt n) :: rest ->
                (match add_all rest with
                 | VInt acc -> VInt (acc + n)
                 | VFloat acc -> VFloat (acc +. float_of_int n)
                 | e -> e)
            | (_, VFloat f) :: rest ->
                (match add_all rest with
                 | VInt acc -> VFloat (float_of_int acc +. f)
                 | VFloat acc -> VFloat (acc +. f)
                 | e -> e)
            | (_, VNA _) :: _ -> make_error TypeError "sum() encountered NA value. Handle missingness explicitly."
            | _ -> make_error TypeError "sum() requires a list of numbers"
          in
          add_all items
      | _ -> make_error ArityError "sum() takes exactly 1 List argument"
    ))
    env
