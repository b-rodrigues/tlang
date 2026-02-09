open Ast

(** Helper: extract numeric values from a VVector or VList for comparison.
    Returns an array of floats or an error. *)
let extract_floats label values =
  let len = Array.length values in
  let result = Array.make len 0.0 in
  let had_error = ref None in
  for i = 0 to len - 1 do
    if !had_error = None then
      match values.(i) with
      | VInt n -> result.(i) <- float_of_int n
      | VFloat f -> result.(i) <- f
      | VNA _ -> had_error := Some (make_error TypeError (label ^ "() encountered NA value. Handle missingness explicitly."))
      | _ -> had_error := Some (make_error TypeError (label ^ "() requires numeric values"))
  done;
  match !had_error with Some e -> Error e | None -> Ok result

(** Helper: convert args to a float array *)
let to_float_array label = function
  | VVector arr -> extract_floats label arr
  | VList items ->
    let arr = Array.of_list (List.map snd items) in
    extract_floats label arr
  | VNA _ -> Error (make_error TypeError (label ^ "() encountered NA value. Handle missingness explicitly."))
  | _ -> Error (make_error TypeError (label ^ "() expects a numeric Vector or List"))

(** Compute sorted indices (ascending) for a float array *)
let argsort (nums : float array) : int array =
  let n = Array.length nums in
  let indices = Array.init n (fun i -> i) in
  Array.stable_sort (fun i j -> compare nums.(i) nums.(j)) indices;
  indices

let register env =
  (* row_number(x): rank from 1..n, ties broken by position *)
  let env = Env.add "row_number"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_float_array "row_number" arg with
         | Error e -> e
         | Ok nums ->
           let n = Array.length nums in
           if n = 0 then VVector [||]
           else
             let sorted_idx = argsort nums in
             let ranks = Array.make n 0 in
             Array.iteri (fun rank_minus_1 orig_idx ->
               ranks.(orig_idx) <- rank_minus_1 + 1
             ) sorted_idx;
             VVector (Array.map (fun r -> VInt r) ranks))
      | _ -> make_error ArityError "row_number() takes exactly 1 argument"
    ))
    env
  in
  (* min_rank(x): ties get minimum rank, gaps after ties *)
  let env = Env.add "min_rank"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_float_array "min_rank" arg with
         | Error e -> e
         | Ok nums ->
           let n = Array.length nums in
           if n = 0 then VVector [||]
           else
             let sorted_idx = argsort nums in
             let ranks = Array.make n 0 in
             let i = ref 0 in
             while !i < n do
               let cur_val = nums.(sorted_idx.(!i)) in
               let start = !i in
               while !i < n && nums.(sorted_idx.(!i)) = cur_val do
                 incr i
               done;
               (* All tied values get rank start+1 *)
               for j = start to !i - 1 do
                 ranks.(sorted_idx.(j)) <- start + 1
               done
             done;
             VVector (Array.map (fun r -> VInt r) ranks))
      | _ -> make_error ArityError "min_rank() takes exactly 1 argument"
    ))
    env
  in
  (* dense_rank(x): ties get same rank, no gaps *)
  let env = Env.add "dense_rank"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_float_array "dense_rank" arg with
         | Error e -> e
         | Ok nums ->
           let n = Array.length nums in
           if n = 0 then VVector [||]
           else
             let sorted_idx = argsort nums in
             let ranks = Array.make n 0 in
             let cur_rank = ref 1 in
             let i = ref 0 in
             while !i < n do
               let cur_val = nums.(sorted_idx.(!i)) in
               while !i < n && nums.(sorted_idx.(!i)) = cur_val do
                 ranks.(sorted_idx.(!i)) <- !cur_rank;
                 incr i
               done;
               incr cur_rank
             done;
             VVector (Array.map (fun r -> VInt r) ranks))
      | _ -> make_error ArityError "dense_rank() takes exactly 1 argument"
    ))
    env
  in
  (* cume_dist(x): proportion of values <= current value *)
  let env = Env.add "cume_dist"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_float_array "cume_dist" arg with
         | Error e -> e
         | Ok nums ->
           let n = Array.length nums in
           if n = 0 then VVector [||]
           else
             let sorted_idx = argsort nums in
             let result = Array.make n 0.0 in
             let i = ref 0 in
             while !i < n do
               let cur_val = nums.(sorted_idx.(!i)) in
               let start = !i in
               while !i < n && nums.(sorted_idx.(!i)) = cur_val do
                 incr i
               done;
               (* All tied values get cume_dist = last_position / n *)
               let cd = float_of_int !i /. float_of_int n in
               for j = start to !i - 1 do
                 result.(sorted_idx.(j)) <- cd
               done
             done;
             VVector (Array.map (fun f -> VFloat f) result))
      | _ -> make_error ArityError "cume_dist() takes exactly 1 argument"
    ))
    env
  in
  (* percent_rank(x): (rank - 1) / (n - 1), 0 for first *)
  let env = Env.add "percent_rank"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_float_array "percent_rank" arg with
         | Error e -> e
         | Ok nums ->
           let n = Array.length nums in
           if n = 0 then VVector [||]
           else if n = 1 then VVector [|VFloat 0.0|]
           else
             (* Use min_rank logic, then scale *)
             let sorted_idx = argsort nums in
             let min_ranks = Array.make n 0 in
             let i = ref 0 in
             while !i < n do
               let cur_val = nums.(sorted_idx.(!i)) in
               let start = !i in
               while !i < n && nums.(sorted_idx.(!i)) = cur_val do
                 incr i
               done;
               for j = start to !i - 1 do
                 min_ranks.(sorted_idx.(j)) <- start + 1
               done
             done;
             let denom = float_of_int (n - 1) in
             VVector (Array.map (fun r ->
               VFloat (float_of_int (r - 1) /. denom)
             ) min_ranks))
      | _ -> make_error ArityError "percent_rank() takes exactly 1 argument"
    ))
    env
  in
  (* ntile(x, n): divide into n approximately equal-sized groups *)
  let env = Env.add "ntile"
    (make_builtin 2 (fun args _env ->
      match args with
      | [arg; VInt num_tiles] when num_tiles > 0 ->
        (match to_float_array "ntile" arg with
         | Error e -> e
         | Ok nums ->
           let n = Array.length nums in
           if n = 0 then VVector [||]
           else
             let sorted_idx = argsort nums in
             let result = Array.make n 0 in
             Array.iteri (fun pos orig_idx ->
               let tile = (pos * num_tiles / n) + 1 in
               result.(orig_idx) <- tile
             ) sorted_idx;
             VVector (Array.map (fun t -> VInt t) result))
      | [_; VInt n] when n <= 0 ->
        make_error ValueError "ntile() requires a positive number of tiles"
      | [_; VInt _] -> make_error TypeError "ntile() expects a numeric Vector or List as first argument"
      | [_; _] -> make_error TypeError "ntile() expects an integer as second argument"
      | _ -> make_error ArityError "ntile() takes exactly 2 arguments"
    ))
    env
  in
  env
