open Ast

(** Helper: get values from a VVector or VList *)
let to_value_array label = function
  | VVector arr -> Ok arr
  | VList items -> Ok (Array.of_list (List.map snd items))
  | VNA _ -> Error (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." label))
  | _ -> Error (Error.type_error (Printf.sprintf "Function `%s` expects a Vector or List." label))

let register env =
  (* cumsum(x): cumulative sum; NA propagates to all subsequent values *)
  let env = Env.add "cumsum"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_value_array "cumsum" arg with
         | Error e -> e
         | Ok arr ->
           let n = Array.length arr in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAFloat) in
             let running = ref 0.0 in
             let all_int = ref true in
             let na_seen = ref false in
             let had_error = ref None in
             for i = 0 to n - 1 do
               if !had_error = None then
                 if !na_seen then
                   result.(i) <- VNA NAFloat
                 else
                   match arr.(i) with
                   | VInt x ->
                     running := !running +. float_of_int x;
                     result.(i) <- if !all_int then VInt (int_of_float !running) else VFloat !running
                   | VFloat f ->
                     all_int := false;
                     running := !running +. f;
                     if i > 0 then
                       for j = 0 to i - 1 do
                         match result.(j) with
                         | VInt v -> result.(j) <- VFloat (float_of_int v)
                         | _ -> ()
                       done;
                     result.(i) <- VFloat !running
                   | VNA _ -> na_seen := true; result.(i) <- VNA NAFloat
                   | _ -> had_error := Some (Error.type_error "Function `cumsum` requires numeric values.")
             done;
             (match !had_error with Some e -> e | None -> VVector result))
      | _ -> Error.arity_error_named "cumsum" ~expected:1 ~received:(List.length args)
    ))
    env
  in
  (* cummin(x): cumulative minimum; NA propagates to all subsequent values *)
  let env = Env.add "cummin"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_value_array "cummin" arg with
         | Error e -> e
         | Ok arr ->
           let n = Array.length arr in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAFloat) in
             let running = ref Float.infinity in
             let all_int = ref true in
             let na_seen = ref false in
             let had_error = ref None in
             for i = 0 to n - 1 do
               if !had_error = None then
                 if !na_seen then
                   result.(i) <- VNA NAFloat
                 else
                   match arr.(i) with
                   | VInt x ->
                     let fx = float_of_int x in
                     running := Float.min !running fx;
                     result.(i) <- if !all_int then VInt (int_of_float !running) else VFloat !running
                   | VFloat f ->
                     all_int := false;
                     running := Float.min !running f;
                     for j = 0 to i - 1 do
                       match result.(j) with
                       | VInt v -> result.(j) <- VFloat (float_of_int v)
                       | _ -> ()
                     done;
                     result.(i) <- VFloat !running
                   | VNA _ -> na_seen := true; result.(i) <- VNA NAFloat
                   | _ -> had_error := Some (Error.type_error "Function `cummin` requires numeric values.")
             done;
             (match !had_error with Some e -> e | None -> VVector result))
      | _ -> Error.arity_error_named "cummin" ~expected:1 ~received:(List.length args)
    ))
    env
  in
  (* cummax(x): cumulative maximum; NA propagates to all subsequent values *)
  let env = Env.add "cummax"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_value_array "cummax" arg with
         | Error e -> e
         | Ok arr ->
           let n = Array.length arr in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAFloat) in
             let running = ref Float.neg_infinity in
             let all_int = ref true in
             let na_seen = ref false in
             let had_error = ref None in
             for i = 0 to n - 1 do
               if !had_error = None then
                 if !na_seen then
                   result.(i) <- VNA NAFloat
                 else
                   match arr.(i) with
                   | VInt x ->
                     let fx = float_of_int x in
                     running := Float.max !running fx;
                     result.(i) <- if !all_int then VInt (int_of_float !running) else VFloat !running
                   | VFloat f ->
                     all_int := false;
                     running := Float.max !running f;
                     for j = 0 to i - 1 do
                       match result.(j) with
                       | VInt v -> result.(j) <- VFloat (float_of_int v)
                       | _ -> ()
                     done;
                     result.(i) <- VFloat !running
                   | VNA _ -> na_seen := true; result.(i) <- VNA NAFloat
                   | _ -> had_error := Some (Error.type_error "Function `cummax` requires numeric values.")
             done;
             (match !had_error with Some e -> e | None -> VVector result))
      | _ -> Error.arity_error_named "cummax" ~expected:1 ~received:(List.length args)
    ))
    env
  in
  (* cummean(x): cumulative mean; NA propagates to all subsequent values *)
  let env = Env.add "cummean"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_value_array "cummean" arg with
         | Error e -> e
         | Ok arr ->
           let n = Array.length arr in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAFloat) in
             let running_sum = ref 0.0 in
             let na_seen = ref false in
             let had_error = ref None in
             for i = 0 to n - 1 do
               if !had_error = None then
                 if !na_seen then
                   result.(i) <- VNA NAFloat
                 else
                   match arr.(i) with
                   | VInt x ->
                     running_sum := !running_sum +. float_of_int x;
                     result.(i) <- VFloat (!running_sum /. float_of_int (i + 1))
                   | VFloat f ->
                     running_sum := !running_sum +. f;
                     result.(i) <- VFloat (!running_sum /. float_of_int (i + 1))
                   | VNA _ -> na_seen := true; result.(i) <- VNA NAFloat
                   | _ -> had_error := Some (Error.type_error "Function `cummean` requires numeric values.")
             done;
             (match !had_error with Some e -> e | None -> VVector result))
      | _ -> Error.arity_error_named "cummean" ~expected:1 ~received:(List.length args)
    ))
    env
  in
  (* cumall(x): cumulative logical AND; NA propagates to all subsequent values *)
  let env = Env.add "cumall"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_value_array "cumall" arg with
         | Error e -> e
         | Ok arr ->
           let n = Array.length arr in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NABool) in
             let running = ref true in
             let na_seen = ref false in
             for i = 0 to n - 1 do
               if !na_seen then
                 result.(i) <- VNA NABool
               else
                 match arr.(i) with
                 | VNA _ -> na_seen := true; result.(i) <- VNA NABool
                 | v ->
                   running := !running && Utils.is_truthy v;
                   result.(i) <- VBool !running
             done;
             VVector result)
      | _ -> Error.arity_error_named "cumall" ~expected:1 ~received:(List.length args)
    ))
    env
  in
  (* cumany(x): cumulative logical OR; NA propagates to all subsequent values *)
  let env = Env.add "cumany"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_value_array "cumany" arg with
         | Error e -> e
         | Ok arr ->
           let n = Array.length arr in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NABool) in
             let running = ref false in
             let na_seen = ref false in
             for i = 0 to n - 1 do
               if !na_seen then
                 result.(i) <- VNA NABool
               else
                 match arr.(i) with
                 | VNA _ -> na_seen := true; result.(i) <- VNA NABool
                 | v ->
                   running := !running || Utils.is_truthy v;
                   result.(i) <- VBool !running
             done;
             VVector result)
      | _ -> Error.arity_error_named "cumany" ~expected:1 ~received:(List.length args)
    ))
    env
  in
  env
