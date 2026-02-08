open Ast

let register ~make_builtin ~make_error env =
  Env.add "exp"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VInt n] -> VFloat (Float.exp (float_of_int n))
      | [VFloat f] -> VFloat (Float.exp f)
      | [VVector arr] ->
          let result = Array.make (Array.length arr) VNull in
          let had_error = ref None in
          Array.iteri (fun i v ->
            if !had_error = None then
              match v with
              | VInt n -> result.(i) <- VFloat (Float.exp (float_of_int n))
              | VFloat f -> result.(i) <- VFloat (Float.exp f)
              | VNA _ -> had_error := Some (make_error TypeError "exp() encountered NA value. Handle missingness explicitly.")
              | _ -> had_error := Some (make_error TypeError "exp() requires numeric values")
          ) arr;
          (match !had_error with Some e -> e | None -> VVector result)
      | [VNA _] -> make_error TypeError "exp() encountered NA value. Handle missingness explicitly."
      | [_] -> make_error TypeError "exp() expects a number or numeric Vector"
      | _ -> make_error ArityError "exp() takes exactly 1 argument"
    ))
    env
