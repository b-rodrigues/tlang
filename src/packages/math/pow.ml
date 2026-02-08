open Ast

let register env =
  Env.add "pow"
    (make_builtin 2 (fun args _env ->
      match args with
      | [VInt b; VInt e] -> VFloat (Float.pow (float_of_int b) (float_of_int e))
      | [VFloat b; VInt e] -> VFloat (Float.pow b (float_of_int e))
      | [VInt b; VFloat e] -> VFloat (Float.pow (float_of_int b) e)
      | [VFloat b; VFloat e] -> VFloat (Float.pow b e)
      | [VVector arr; exp_val] ->
          let exp_f = match exp_val with
            | VInt n -> Some (float_of_int n)
            | VFloat f -> Some f
            | _ -> None
          in
          (match exp_f with
           | None -> make_error TypeError "pow() expects a numeric exponent"
           | Some e ->
             let result = Array.make (Array.length arr) VNull in
             let had_error = ref None in
             Array.iteri (fun i v ->
               if !had_error = None then
                 match v with
                 | VInt n -> result.(i) <- VFloat (Float.pow (float_of_int n) e)
                 | VFloat f -> result.(i) <- VFloat (Float.pow f e)
                 | VNA _ -> had_error := Some (make_error TypeError "pow() encountered NA value. Handle missingness explicitly.")
                 | _ -> had_error := Some (make_error TypeError "pow() requires numeric values")
             ) arr;
             (match !had_error with Some e -> e | None -> VVector result))
      | [VNA _; _] | [_; VNA _] -> make_error TypeError "pow() encountered NA value. Handle missingness explicitly."
      | [_; _] -> make_error TypeError "pow() expects numeric arguments"
      | _ -> make_error ArityError "pow() takes exactly 2 arguments"
    ))
    env
