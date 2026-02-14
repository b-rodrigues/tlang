open Ast

let register env =
  Env.add "sqrt"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VInt n] ->
          if n < 0 then Error.value_error "Function `sqrt` is undefined for negative numbers."
          else VFloat (Float.sqrt (float_of_int n))
      | [VFloat f] ->
          if f < 0.0 then Error.value_error "Function `sqrt` is undefined for negative numbers."
          else VFloat (Float.sqrt f)
      | [VVector arr] ->
          let result = Array.make (Array.length arr) VNull in
          let had_error = ref None in
          Array.iteri (fun i v ->
            if !had_error = None then
              match v with
              | VInt n ->
                  if n < 0 then had_error := Some (Error.value_error "Function `sqrt` is undefined for negative numbers.")
                  else result.(i) <- VFloat (Float.sqrt (float_of_int n))
              | VFloat f ->
                  if f < 0.0 then had_error := Some (Error.value_error "Function `sqrt` is undefined for negative numbers.")
                  else result.(i) <- VFloat (Float.sqrt f)
              | VNA _ -> had_error := Some (Error.type_error "Function `sqrt` encountered NA value. Handle missingness explicitly.")
              | _ -> had_error := Some (Error.type_error "Function `sqrt` requires numeric values.")
          ) arr;
          (match !had_error with Some e -> e | None -> VVector result)
      | [VNA _] -> Error.type_error "Function `sqrt` encountered NA value. Handle missingness explicitly."
      | [_] -> Error.type_error "Function `sqrt` expects a number or numeric Vector."
      | _ -> Error.arity_error_named "sqrt" ~expected:1 ~received:(List.length args)
    ))
    env
