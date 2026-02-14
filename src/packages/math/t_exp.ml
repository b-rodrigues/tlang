open Ast

let register env =
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
              | VNA _ -> had_error := Some (Error.type_error "Function `exp` encountered NA value. Handle missingness explicitly.")
              | _ -> had_error := Some (Error.type_error "Function `exp` requires numeric values.")
          ) arr;
          (match !had_error with Some e -> e | None -> VVector result)
      | [VNA _] -> Error.type_error "Function `exp` encountered NA value. Handle missingness explicitly."
      | [_] -> Error.type_error "Function `exp` expects a number or numeric Vector."
      | _ -> Error.arity_error_named "exp" ~expected:1 ~received:(List.length args)
    ))
    env
