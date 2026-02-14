open Ast

(** Helper: get values from a VVector or VList *)
let to_value_array label = function
  | VVector arr -> Ok arr
  | VList items -> Ok (Array.of_list (List.map snd items))
  | VNA _ -> Error (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." label))
  | _ -> Error (Error.type_error (Printf.sprintf "Function `%s` expects a Vector or List." label))

let register env =
  (* lag(x) or lag(x, n): shift values forward, filling with NA *)
  let env = Env.add "lag"
    (make_builtin ~variadic:true 1 (fun args _env ->
      match args with
      | [arg] | [arg; VInt 1] ->
        (match to_value_array "lag" arg with
         | Error e -> e
         | Ok arr ->
           let n = Array.length arr in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAGeneric) in
             for i = 1 to n - 1 do
               result.(i) <- arr.(i - 1)
             done;
             VVector result)
      | [arg; VInt offset] when offset >= 0 ->
        (match to_value_array "lag" arg with
         | Error e -> e
         | Ok arr ->
           let n = Array.length arr in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAGeneric) in
             for i = offset to n - 1 do
               result.(i) <- arr.(i - offset)
             done;
             VVector result)
      | [_; VInt _] -> Error.value_error "Function `lag` offset must be non-negative."
      | [_; _] -> Error.type_error "Function `lag` expects an integer offset."
      | _ -> Error.make_error ArityError "Function `lag` takes 1 or 2 arguments."
    ))
    env
  in
  (* lead(x) or lead(x, n): shift values backward, filling with NA *)
  let env = Env.add "lead"
    (make_builtin ~variadic:true 1 (fun args _env ->
      match args with
      | [arg] | [arg; VInt 1] ->
        (match to_value_array "lead" arg with
         | Error e -> e
         | Ok arr ->
           let n = Array.length arr in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAGeneric) in
             for i = 0 to n - 2 do
               result.(i) <- arr.(i + 1)
             done;
             VVector result)
      | [arg; VInt offset] when offset >= 0 ->
        (match to_value_array "lead" arg with
         | Error e -> e
         | Ok arr ->
           let n = Array.length arr in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAGeneric) in
             for i = 0 to n - 1 - offset do
               result.(i) <- arr.(i + offset)
             done;
             VVector result)
      | [_; VInt _] -> Error.value_error "Function `lead` offset must be non-negative."
      | [_; _] -> Error.type_error "Function `lead` expects an integer offset."
      | _ -> Error.make_error ArityError "Function `lead` takes 1 or 2 arguments."
    ))
    env
  in
  env
