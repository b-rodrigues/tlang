open Ast

(** Helper: get values from a VVector or VList *)
let to_value_array = function
  | VVector arr -> Ok arr
  | VList items -> Ok (Array.of_list (List.map snd items))
  | VNA _ -> Error (make_error TypeError "encountered NA value. Handle missingness explicitly.")
  | _ -> Error (make_error TypeError "expects a Vector or List")

let register env =
  (* lag(x) or lag(x, n): shift values forward, filling with NA *)
  let env = Env.add "lag"
    (make_builtin ~variadic:true 1 (fun args _env ->
      match args with
      | [arg] | [arg; VInt 1] ->
        (match to_value_array arg with
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
        (match to_value_array arg with
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
      | [_; VInt _] -> make_error ValueError "lag() offset must be non-negative"
      | [_; _] -> make_error TypeError "lag() expects an integer offset"
      | _ -> make_error ArityError "lag() takes 1 or 2 arguments"
    ))
    env
  in
  (* lead(x) or lead(x, n): shift values backward, filling with NA *)
  let env = Env.add "lead"
    (make_builtin ~variadic:true 1 (fun args _env ->
      match args with
      | [arg] | [arg; VInt 1] ->
        (match to_value_array arg with
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
        (match to_value_array arg with
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
      | [_; VInt _] -> make_error ValueError "lead() offset must be non-negative"
      | [_; _] -> make_error TypeError "lead() expects an integer offset"
      | _ -> make_error ArityError "lead() takes 1 or 2 arguments"
    ))
    env
  in
  env
