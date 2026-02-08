open Ast

let register ~make_builtin ~make_error env =
  Env.add "sqrt"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VInt n] ->
          if n < 0 then make_error ValueError "sqrt() is undefined for negative numbers"
          else VFloat (Float.sqrt (float_of_int n))
      | [VFloat f] ->
          if f < 0.0 then make_error ValueError "sqrt() is undefined for negative numbers"
          else VFloat (Float.sqrt f)
      | [VVector arr] ->
          let result = Array.make (Array.length arr) VNull in
          let had_error = ref None in
          Array.iteri (fun i v ->
            if !had_error = None then
              match v with
              | VInt n ->
                  if n < 0 then had_error := Some (make_error ValueError "sqrt() is undefined for negative numbers")
                  else result.(i) <- VFloat (Float.sqrt (float_of_int n))
              | VFloat f ->
                  if f < 0.0 then had_error := Some (make_error ValueError "sqrt() is undefined for negative numbers")
                  else result.(i) <- VFloat (Float.sqrt f)
              | VNA _ -> had_error := Some (make_error TypeError "sqrt() encountered NA value. Handle missingness explicitly.")
              | _ -> had_error := Some (make_error TypeError "sqrt() requires numeric values")
          ) arr;
          (match !had_error with Some e -> e | None -> VVector result)
      | [VNA _] -> make_error TypeError "sqrt() encountered NA value. Handle missingness explicitly."
      | [_] -> make_error TypeError "sqrt() expects a number or numeric Vector"
      | _ -> make_error ArityError "sqrt() takes exactly 1 argument"
    ))
    env
