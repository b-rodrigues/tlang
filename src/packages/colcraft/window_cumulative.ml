open Ast

(** Helper: get values from a VVector or VList *)
let to_value_array label = function
  | VVector arr -> Ok arr
  | VList items -> Ok (Array.of_list (List.map snd items))
  | VNA _ -> Error (Error.type_error (Printf.sprintf "Function `%s` encountered NA value. Handle missingness explicitly." label))
  | _ -> Error (Error.type_error (Printf.sprintf "Function `%s` expects a Vector or List." label))

let register env =
  (*
  --# Cumulative Sum
  --#
  --# Calculates the cumulative sum of a vector.
  --#
  --# @name cumsum
  --# @param x :: Vector The input numeric vector.
  --# @return :: Vector The cumulative sum.
  --# @example
  --#   cumsum([1, 2, 3])
  --#   -- Returns: [1, 3, 6]
  --# @family colcraft
  --# @seealso sum, cummax, cummin
  --# @export
  *)
  (* cumsum(x): cumulative sum; NA propagates to all subsequent values *)
  let env = Env.add "cumsum"
    (make_builtin ~name:"cumsum" 1 (fun args _env ->
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
  (*
  --# Cumulative Minimum
  --#
  --# Calculates the cumulative minimum of a vector.
  --#
  --# @name cummin
  --# @param x :: Vector The input numeric vector.
  --# @return :: Vector The cumulative minimum.
  --# @example
  --#   cummin([3, 2, 4, 1])
  --#   -- Returns: [3, 2, 2, 1]
  --# @family colcraft
  --# @seealso min, cummax, cumsum
  --# @export
  *)
  (* cummin(x): cumulative minimum; NA propagates to all subsequent values *)
  let env = Env.add "cummin"
    (make_builtin ~name:"cummin" 1 (fun args _env ->
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
  (*
  --# Cumulative Maximum
  --#
  --# Calculates the cumulative maximum of a vector.
  --#
  --# @name cummax
  --# @param x :: Vector The input numeric vector.
  --# @return :: Vector The cumulative maximum.
  --# @example
  --#   cummax([1, 3, 2, 4])
  --#   -- Returns: [1, 3, 3, 4]
  --# @family colcraft
  --# @seealso max, cummin, cumsum
  --# @export
  *)
  (* cummax(x): cumulative maximum; NA propagates to all subsequent values *)
  let env = Env.add "cummax"
    (make_builtin ~name:"cummax" 1 (fun args _env ->
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
  (*
  --# Cumulative Mean
  --#
  --# Calculates the cumulative mean of a vector.
  --#
  --# @name cummean
  --# @param x :: Vector The input numeric vector.
  --# @param na_rm :: Bool = false Remove NA values before computation.
  --# @return :: Vector The cumulative mean.
  --# @example
  --#   cummean([1, 2, 3])
  --#   -- Returns: [1.0, 1.5, 2.0]
  --#
  --#   cummean([1, NA, 3], na_rm: true)
  --#   -- Returns: [1.0, 1.0, 2.0]
  --# @family colcraft
  --# @seealso mean, cumsum
  --# @export
  *)
  (* cummean(x, na_rm=false): cumulative mean *)
  let env = Env.add "cummean"
    (make_builtin_named ~name:"cummean" ~variadic:true 1 (fun named_args _env ->
      let na_rm = List.exists (fun (name, v) ->
        name = Some "na_rm" && (match v with VBool true -> true | _ -> false)
      ) named_args in
      let args = List.filter (fun (name, _) -> name <> Some "na_rm") named_args |> List.map snd in
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
             let running_count = ref 0 in
             let na_seen = ref false in
             let had_error = ref None in
             for i = 0 to n - 1 do
               if !had_error = None then
                 if not na_rm && !na_seen then
                   result.(i) <- VNA NAFloat
                 else
                   match arr.(i) with
                   | VInt x ->
                     running_sum := !running_sum +. float_of_int x;
                     incr running_count;
                     result.(i) <- VFloat (!running_sum /. float_of_int !running_count)
                   | VFloat f ->
                     running_sum := !running_sum +. f;
                     incr running_count;
                     result.(i) <- VFloat (!running_sum /. float_of_int !running_count)
                   | VNA _ -> 
                     if na_rm then 
                       result.(i) <- if !running_count = 0 then VNA NAFloat else VFloat (!running_sum /. float_of_int !running_count)
                     else (
                       na_seen := true; 
                       result.(i) <- VNA NAFloat
                     )
                   | _ -> had_error := Some (Error.type_error "Function `cummean` requires numeric values.")
             done;
             (match !had_error with Some e -> e | None -> VVector result))
      | _ -> Error.arity_error_named "cummean" ~expected:1 ~received:(List.length args)
    ))
    env
  in
  (*
  --# Cumulative All
  --#
  --# Calculates the cumulative logical AND of a vector.
  --#
  --# @name cumall
  --# @param x :: Vector The input boolean vector.
  --# @return :: Vector The cumulative AND.
  --# @example
  --#   cumall([true, true, false, true])
  --#   -- Returns: [true, true, false, false]
  --# @family colcraft
  --# @seealso cumany
  --# @export
  *)
  (* cumall(x): cumulative logical AND; NA propagates to all subsequent values *)
  let env = Env.add "cumall"
    (make_builtin ~name:"cumall" 1 (fun args _env ->
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
  (*
  --# Cumulative Any
  --#
  --# Calculates the cumulative logical OR of a vector.
  --#
  --# @name cumany
  --# @param x :: Vector The input boolean vector.
  --# @return :: Vector The cumulative OR.
  --# @example
  --#   cumany([false, false, true, false])
  --#   -- Returns: [false, false, true, true]
  --# @family colcraft
  --# @seealso cumall
  --# @export
  *)
  (* cumany(x): cumulative logical OR; NA propagates to all subsequent values *)
  let env = Env.add "cumany"
    (make_builtin ~name:"cumany" 1 (fun args _env ->
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
