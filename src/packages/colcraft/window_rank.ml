open Ast

(** Helper: extract numeric values from a VVector or VList, tolerating NA.
    Returns an array of (float option) — None for NA positions — or an error
    for non-numeric values. *)
let extract_floats_na label values =
  let len = Array.length values in
  let result = Array.make len None in
  let had_error = ref None in
  for i = 0 to len - 1 do
    if !had_error = None then
      match values.(i) with
      | VInt n -> result.(i) <- Some (float_of_int n)
      | VFloat f -> result.(i) <- Some f
      | VNA _ -> result.(i) <- None
      | _ -> had_error := Some (make_error TypeError (label ^ "() requires numeric values"))
  done;
  match !had_error with Some e -> Error e | None -> Ok result

(** Helper: convert args to a (float option) array, tolerating NA *)
let to_float_array_na label = function
  | VVector arr -> extract_floats_na label arr
  | VList items ->
    let arr = Array.of_list (List.map snd items) in
    extract_floats_na label arr
  | VNA _ -> Ok [|None|]
  | _ -> Error (make_error TypeError (label ^ "() expects a numeric Vector or List"))

(** Collect indices of non-NA positions and their float values *)
let non_na_indices (nums : float option array) : (int * float) array =
  let n = Array.length nums in
  let count = ref 0 in
  Array.iter (fun v -> if v <> None then incr count) nums;
  let result = Array.make !count (0, 0.0) in
  let pos = ref 0 in
  for i = 0 to n - 1 do
    match nums.(i) with
    | Some f -> result.(!pos) <- (i, f); incr pos
    | None -> ()
  done;
  result

(** Compute sorted indices (ascending) for an array of (original_index, float) pairs.
    Returns sorted array of (original_index, float). *)
let argsort_pairs (pairs : (int * float) array) : (int * float) array =
  let copy = Array.copy pairs in
  Array.stable_sort (fun (_, a) (_, b) -> compare a b) copy;
  copy

let register env =
  (* row_number(x): rank from 1..n among non-NA values, NA positions get NA *)
  let env = Env.add "row_number"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_float_array_na "row_number" arg with
         | Error e -> e
         | Ok nums ->
           let n = Array.length nums in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAInt) in
             let pairs = non_na_indices nums in
             let sorted = argsort_pairs pairs in
             Array.iteri (fun rank_minus_1 (orig_idx, _) ->
               result.(orig_idx) <- VInt (rank_minus_1 + 1)
             ) sorted;
             VVector result)
      | _ -> make_error ArityError "row_number() takes exactly 1 argument"
    ))
    env
  in
  (* min_rank(x): ties get minimum rank, gaps after ties; NA positions get NA *)
  let env = Env.add "min_rank"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_float_array_na "min_rank" arg with
         | Error e -> e
         | Ok nums ->
           let n = Array.length nums in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAInt) in
             let pairs = non_na_indices nums in
             let m = Array.length pairs in
             if m = 0 then VVector result
             else begin
               let sorted = argsort_pairs pairs in
               let i = ref 0 in
               while !i < m do
                 let (_, cur_val) = sorted.(!i) in
                 let start = !i in
                 while !i < m && snd sorted.(!i) = cur_val do
                   incr i
                 done;
                 for j = start to !i - 1 do
                   let (orig_idx, _) = sorted.(j) in
                   result.(orig_idx) <- VInt (start + 1)
                 done
               done;
               VVector result
             end)
      | _ -> make_error ArityError "min_rank() takes exactly 1 argument"
    ))
    env
  in
  (* dense_rank(x): ties get same rank, no gaps; NA positions get NA *)
  let env = Env.add "dense_rank"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_float_array_na "dense_rank" arg with
         | Error e -> e
         | Ok nums ->
           let n = Array.length nums in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAInt) in
             let pairs = non_na_indices nums in
             let m = Array.length pairs in
             if m = 0 then VVector result
             else begin
               let sorted = argsort_pairs pairs in
               let cur_rank = ref 1 in
               let i = ref 0 in
               while !i < m do
                 let (_, cur_val) = sorted.(!i) in
                 while !i < m && snd sorted.(!i) = cur_val do
                   let (orig_idx, _) = sorted.(!i) in
                   result.(orig_idx) <- VInt !cur_rank;
                   incr i
                 done;
                 incr cur_rank
               done;
               VVector result
             end)
      | _ -> make_error ArityError "dense_rank() takes exactly 1 argument"
    ))
    env
  in
  (* cume_dist(x): proportion of non-NA values <= current value; NA positions get NA *)
  let env = Env.add "cume_dist"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_float_array_na "cume_dist" arg with
         | Error e -> e
         | Ok nums ->
           let n = Array.length nums in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAFloat) in
             let pairs = non_na_indices nums in
             let m = Array.length pairs in
             if m = 0 then VVector result
             else begin
               let sorted = argsort_pairs pairs in
               let i = ref 0 in
               while !i < m do
                 let (_, cur_val) = sorted.(!i) in
                 let start = !i in
                 while !i < m && snd sorted.(!i) = cur_val do
                   incr i
                 done;
                 let cd = float_of_int !i /. float_of_int m in
                 for j = start to !i - 1 do
                   let (orig_idx, _) = sorted.(j) in
                   result.(orig_idx) <- VFloat cd
                 done
               done;
               VVector result
             end)
      | _ -> make_error ArityError "cume_dist() takes exactly 1 argument"
    ))
    env
  in
  (* percent_rank(x): (rank - 1) / (n - 1) among non-NA values; NA positions get NA *)
  let env = Env.add "percent_rank"
    (make_builtin 1 (fun args _env ->
      match args with
      | [arg] ->
        (match to_float_array_na "percent_rank" arg with
         | Error e -> e
         | Ok nums ->
           let n = Array.length nums in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAFloat) in
             let pairs = non_na_indices nums in
             let m = Array.length pairs in
             if m = 0 then VVector result
             else if m = 1 then begin
               let (orig_idx, _) = pairs.(0) in
               result.(orig_idx) <- VFloat 0.0;
               VVector result
             end else begin
               let sorted = argsort_pairs pairs in
               let min_ranks = Array.make m 0 in
               let i = ref 0 in
               while !i < m do
                 let (_, cur_val) = sorted.(!i) in
                 let start = !i in
                 while !i < m && snd sorted.(!i) = cur_val do
                   incr i
                 done;
                 for j = start to !i - 1 do
                   min_ranks.(j) <- start + 1
                 done
               done;
               let denom = float_of_int (m - 1) in
               Array.iteri (fun sorted_pos rank ->
                 let (orig_idx, _) = sorted.(sorted_pos) in
                 result.(orig_idx) <- VFloat (float_of_int (rank - 1) /. denom)
               ) min_ranks;
               VVector result
             end)
      | _ -> make_error ArityError "percent_rank() takes exactly 1 argument"
    ))
    env
  in
  (* ntile(x, n): divide non-NA values into n approximately equal-sized groups; NA positions get NA *)
  (* Matches R's dplyr::ntile: first (len %% n) groups have (len / n + 1) elements,
     remaining groups have (len / n) elements. Assignment is based on rank. *)
  let env = Env.add "ntile"
    (make_builtin 2 (fun args _env ->
      match args with
      | [arg; VInt num_tiles] when num_tiles > 0 ->
        (match to_float_array_na "ntile" arg with
         | Error e -> e
         | Ok nums ->
           let n = Array.length nums in
           if n = 0 then VVector [||]
           else
             let result = Array.make n (VNA NAInt) in
             let pairs = non_na_indices nums in
             let m = Array.length pairs in
             if m = 0 then VVector result
             else begin
               let sorted = argsort_pairs pairs in
               let grp_len = m / num_tiles in
               let remainder = m mod num_tiles in
               let tiles_for_sorted = Array.make m 0 in
               let pos = ref 0 in
               for tile = 1 to num_tiles do
                 let size = if tile <= remainder then grp_len + 1 else grp_len in
                 for _ = 1 to size do
                   if !pos < m then begin
                     tiles_for_sorted.(!pos) <- tile;
                     incr pos
                   end
                 done
               done;
               Array.iteri (fun sorted_pos (orig_idx, _) ->
                 result.(orig_idx) <- VInt tiles_for_sorted.(sorted_pos)
               ) sorted;
               VVector result
             end)
      | [_; VInt n] when n <= 0 ->
        make_error ValueError "ntile() requires a positive number of tiles"
      | [_; _] -> make_error TypeError "ntile() expects an integer as second argument"
      | _ -> make_error ArityError "ntile() takes exactly 2 arguments"
    ))
    env
  in
  env
