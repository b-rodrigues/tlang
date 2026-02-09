open Ast

(** Helper: get values from a VVector or VList *)
let to_value_array label = function
  | VVector arr -> Ok arr
  | VList items -> Ok (Array.of_list (List.map snd items))
  | VNA _ -> Error (make_error TypeError (label ^ "() encountered NA value. Handle missingness explicitly."))
  | _ -> Error (make_error TypeError (label ^ "() expects a Vector or List"))

let register env =
  (* cumsum(x): cumulative sum *)
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
             let result = Array.make n (VNA NAGeneric) in
             let running = ref 0.0 in
             let all_int = ref true in
             let had_error = ref None in
             for i = 0 to n - 1 do
               if !had_error = None then
                 match arr.(i) with
                 | VInt x ->
                   running := !running +. float_of_int x;
                   result.(i) <- if !all_int then VInt (int_of_float !running) else VFloat !running
                 | VFloat f ->
                   all_int := false;
                   running := !running +. f;
                   (* Backfill previous int results as float *)
                   if i > 0 then
                     for j = 0 to i - 1 do
                       match result.(j) with
                       | VInt v -> result.(j) <- VFloat (float_of_int v)
                       | _ -> ()
                     done;
                   result.(i) <- VFloat !running
                 | VNA _ -> had_error := Some (make_error TypeError "cumsum() encountered NA value. Handle missingness explicitly.")
                 | _ -> had_error := Some (make_error TypeError "cumsum() requires numeric values")
             done;
             (match !had_error with Some e -> e | None -> VVector result))
      | _ -> make_error ArityError "cumsum() takes exactly 1 argument"
    ))
    env
  in
  (* cummin(x): cumulative minimum *)
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
             let result = Array.make n (VNA NAGeneric) in
             let running = ref Float.infinity in
             let all_int = ref true in
             let had_error = ref None in
             for i = 0 to n - 1 do
               if !had_error = None then
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
                 | VNA _ -> had_error := Some (make_error TypeError "cummin() encountered NA value. Handle missingness explicitly.")
                 | _ -> had_error := Some (make_error TypeError "cummin() requires numeric values")
             done;
             (match !had_error with Some e -> e | None -> VVector result))
      | _ -> make_error ArityError "cummin() takes exactly 1 argument"
    ))
    env
  in
  (* cummax(x): cumulative maximum *)
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
             let result = Array.make n (VNA NAGeneric) in
             let running = ref Float.neg_infinity in
             let all_int = ref true in
             let had_error = ref None in
             for i = 0 to n - 1 do
               if !had_error = None then
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
                 | VNA _ -> had_error := Some (make_error TypeError "cummax() encountered NA value. Handle missingness explicitly.")
                 | _ -> had_error := Some (make_error TypeError "cummax() requires numeric values")
             done;
             (match !had_error with Some e -> e | None -> VVector result))
      | _ -> make_error ArityError "cummax() takes exactly 1 argument"
    ))
    env
  in
  (* cummean(x): cumulative mean *)
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
             let result = Array.make n (VNA NAGeneric) in
             let running_sum = ref 0.0 in
             let had_error = ref None in
             for i = 0 to n - 1 do
               if !had_error = None then
                 match arr.(i) with
                 | VInt x ->
                   running_sum := !running_sum +. float_of_int x;
                   result.(i) <- VFloat (!running_sum /. float_of_int (i + 1))
                 | VFloat f ->
                   running_sum := !running_sum +. f;
                   result.(i) <- VFloat (!running_sum /. float_of_int (i + 1))
                 | VNA _ -> had_error := Some (make_error TypeError "cummean() encountered NA value. Handle missingness explicitly.")
                 | _ -> had_error := Some (make_error TypeError "cummean() requires numeric values")
             done;
             (match !had_error with Some e -> e | None -> VVector result))
      | _ -> make_error ArityError "cummean() takes exactly 1 argument"
    ))
    env
  in
  (* cumall(x): cumulative logical AND *)
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
             let result = Array.make n (VBool true) in
             let running = ref true in
             for i = 0 to n - 1 do
               running := !running && Utils.is_truthy arr.(i);
               result.(i) <- VBool !running
             done;
             VVector result)
      | _ -> make_error ArityError "cumall() takes exactly 1 argument"
    ))
    env
  in
  (* cumany(x): cumulative logical OR *)
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
             let result = Array.make n (VBool false) in
             let running = ref false in
             for i = 0 to n - 1 do
               running := !running || Utils.is_truthy arr.(i);
               result.(i) <- VBool !running
             done;
             VVector result)
      | _ -> make_error ArityError "cumany() takes exactly 1 argument"
    ))
    env
  in
  env
