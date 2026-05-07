(* src/packages/stats/math_utils.ml *)

open Ast

(** Shared helpers for descriptive statistics. *)

let collection_values ~label = function
  | VVector arr -> Ok arr
  | VList items -> Ok (Array.of_list (List.map snd items))
  | VNA _ -> Error (Error.na_value_error ~na_rm:true label)
  | _ ->
      Error
        (Error.type_error
           (Printf.sprintf
              "Function `%s` expects a numeric List or Vector."
              label))

let numeric_weight_error label =
  Error.type_error
    (Printf.sprintf
       "Function `%s` expects `weight` to be a numeric List or Vector."
       label)

let invalid_weight_value_error label =
  Error.value_error
    (Printf.sprintf
       "Function `%s` expects non-negative finite weights."
       label)

let invalid_weight_total_error label =
  Error.value_error
    (Printf.sprintf
       "Function `%s` expects `weight` to contain at least one positive value."
       label)

let invalid_weight_length_error label =
  Error.value_error
    (Printf.sprintf
       "Function `%s` expects `weight` to have the same length as the data."
       label)

let invalid_weight_pair_length_error label =
  Error.value_error
    (Printf.sprintf
       "Function `%s` expects `weight` to have the same length as both inputs."
       label)

let numeric_value_of_value ~label = function
  | VInt n -> Ok (float_of_int n)
  | VFloat f when Float.is_finite f -> Ok f
  | VFloat _ ->
      Error
        (Error.type_error
           (Printf.sprintf "Function `%s` requires numeric values." label))
  | VNA _ -> Error (Error.na_value_error ~na_rm:true label)
  | _ ->
      Error
        (Error.type_error
           (Printf.sprintf "Function `%s` requires numeric values." label))

let weight_value_of_value ~label = function
  | VInt n when n >= 0 -> Ok (float_of_int n)
  | VFloat f when Float.is_finite f && f >= 0.0 -> Ok f
  | VInt _ | VFloat _ -> Error (invalid_weight_value_error label)
  | VNA _ -> Error (Error.na_value_error ~na_rm:true label)
  | _ -> Error (numeric_weight_error label)

let filter_positive_weights xs ws =
  let kept = ref [] in
  for i = 0 to Array.length xs - 1 do
    if ws.(i) > 0.0 then kept := (xs.(i), ws.(i)) :: !kept
  done;
  let kept = !kept in
  let kept = List.rev kept in
  let xs' = Array.of_list (List.map fst kept) in
  let ws' = Array.of_list (List.map snd kept) in
  (xs', ws')

let extract_numeric_array ~label ~na_rm v =
  match collection_values ~label v with
  | Error _ as err -> err
  | Ok values ->
      let acc = ref [] in
      let had_error = ref None in
      for i = 0 to Array.length values - 1 do
        if !had_error = None then
          match values.(i) with
          | VInt n -> acc := float_of_int n :: !acc
          | VFloat f when Float.is_finite f -> acc := f :: !acc
          | VFloat _ ->
              had_error :=
                Some
                  (Error.type_error
                     (Printf.sprintf
                        "Function `%s` requires numeric values."
                        label))
          | VNA _ when na_rm -> ()
          | VNA _ ->
              had_error := Some (Error.na_value_error ~na_rm:true label)
          | _ ->
              had_error :=
                Some
                  (Error.type_error
                     (Printf.sprintf
                        "Function `%s` requires numeric values."
                        label))
      done;
      match !had_error with
      | Some e -> Error e
      | None -> Ok (Array.of_list (List.rev !acc))

let extract_numeric_array_with_weights ~label ~na_rm x weight_v =
  match (collection_values ~label x, collection_values ~label weight_v) with
  | Error _ as err, _ -> err
  | _, Error _ -> Error (numeric_weight_error label)
  | Ok xs_raw, Ok ws_raw ->
      if Array.length xs_raw <> Array.length ws_raw then
        Error (invalid_weight_length_error label)
      else
        let xs = ref [] in
        let ws = ref [] in
        let had_error = ref None in
        for i = 0 to Array.length xs_raw - 1 do
          if !had_error = None then
            match
              ( numeric_value_of_value ~label xs_raw.(i),
                weight_value_of_value ~label ws_raw.(i) )
            with
            | Ok xv, Ok w when w > 0.0 ->
                xs := xv :: !xs;
                ws := w :: !ws
            | Ok _, Ok _ -> ()
            | (Error _, _) | (_, Error _)
              when na_rm
                   &&
                   (match (xs_raw.(i), ws_raw.(i)) with
                    | VNA _, _ | _, VNA _ -> true
                    | _ -> false) -> ()
            | Error e, _ | _, Error e -> had_error := Some e
        done;
        (match !had_error with
         | Some e -> Error e
         | None ->
             let xs = Array.of_list (List.rev !xs) in
             let ws = Array.of_list (List.rev !ws) in
             if Array.length ws = 0 then Error (invalid_weight_total_error label)
             else Ok (xs, ws))

let extract_paired_numeric_arrays ~label ~na_rm x y =
  match (collection_values ~label x, collection_values ~label y) with
  | Error _ as err, _ -> err
  | _, (Error _ as err) -> err
  | Ok xs_raw, Ok ys_raw ->
      if Array.length xs_raw <> Array.length ys_raw then
        Error
          (Error.value_error
             (Printf.sprintf
                "Function `%s` requires vectors of equal length."
                label))
      else
        let xs = ref [] in
        let ys = ref [] in
        let had_error = ref None in
        for i = 0 to Array.length xs_raw - 1 do
          if !had_error = None then
            match
              (numeric_value_of_value ~label xs_raw.(i),
               numeric_value_of_value ~label ys_raw.(i))
            with
            | Ok xv, Ok yv ->
                xs := xv :: !xs;
                ys := yv :: !ys
            | (Error _, _) | (_, Error _) when na_rm &&
                                           (match xs_raw.(i), ys_raw.(i) with
                                            | VNA _, _ | _, VNA _ -> true
                                            | _ -> false) -> ()
            | Error e, _ | _, Error e -> had_error := Some e
        done;
        (match !had_error with
         | Some e -> Error e
         | None ->
             Ok
               (Array.of_list (List.rev !xs), Array.of_list (List.rev !ys)))

let extract_paired_numeric_arrays_with_weights ~label ~na_rm x y weight_v =
  match
    ( collection_values ~label x,
      collection_values ~label y,
      collection_values ~label weight_v )
  with
  | Error _ as err, _, _ -> err
  | _, (Error _ as err), _ -> err
  | _, _, Error _ -> Error (numeric_weight_error label)
  | Ok xs_raw, Ok ys_raw, Ok ws_raw ->
      if Array.length xs_raw <> Array.length ys_raw then
        Error
          (Error.value_error
             (Printf.sprintf
                "Function `%s` requires vectors of equal length."
                label))
      else if Array.length xs_raw <> Array.length ws_raw then
        Error (invalid_weight_pair_length_error label)
      else
        let xs = ref [] in
        let ys = ref [] in
        let ws = ref [] in
        let had_error = ref None in
        for i = 0 to Array.length xs_raw - 1 do
          if !had_error = None then
            match
              ( numeric_value_of_value ~label xs_raw.(i),
                numeric_value_of_value ~label ys_raw.(i),
                weight_value_of_value ~label ws_raw.(i) )
            with
            | Ok xv, Ok yv, Ok w when w > 0.0 ->
                xs := xv :: !xs;
                ys := yv :: !ys;
                ws := w :: !ws
            | Ok _, Ok _, Ok _ -> ()
            | (Error _, _, _) | (_, Error _, _) | (_, _, Error _)
              when na_rm
                   &&
                   (match (xs_raw.(i), ys_raw.(i), ws_raw.(i)) with
                    | VNA _, _, _ | _, VNA _, _ | _, _, VNA _ -> true
                    | _ -> false) -> ()
            | Error e, _, _ | _, Error e, _ | _, _, Error e ->
                had_error := Some e
        done;
        (match !had_error with
         | Some e -> Error e
         | None ->
             let xs = Array.of_list (List.rev !xs) in
             let ys = Array.of_list (List.rev !ys) in
             let ws = Array.of_list (List.rev !ws) in
             if Array.length ws = 0 then Error (invalid_weight_total_error label)
             else Ok (xs, ys, ws))

let sum_array arr = Array.fold_left ( +. ) 0.0 arr

let mean_array arr =
  let n = Array.length arr in
  if n = 0 then None else Some (sum_array arr /. float_of_int n)

let weighted_mean_array xs ws =
  let total_w = sum_array ws in
  if total_w <= 0.0 then None
  else
    let s = ref 0.0 in
    for i = 0 to Array.length xs - 1 do
      s := !s +. (ws.(i) *. xs.(i))
    done;
    Some (!s /. total_w)

let sample_variance_array xs =
  match mean_array xs with
  | None -> None
  | Some m ->
      let n = Array.length xs in
      if n < 2 then None
      else
        let ss = ref 0.0 in
        for i = 0 to n - 1 do
          let d = xs.(i) -. m in
          ss := !ss +. (d *. d)
        done;
        Some (!ss /. float_of_int (n - 1))

let weighted_variance_population xs ws =
  match weighted_mean_array xs ws with
  | None -> None
  | Some m ->
      let total_w = sum_array ws in
      let ss = ref 0.0 in
      for i = 0 to Array.length xs - 1 do
        let d = xs.(i) -. m in
        ss := !ss +. (ws.(i) *. d *. d)
      done;
      Some (!ss /. total_w)

let sample_covariance_array xs ys =
  match (mean_array xs, mean_array ys) with
  | Some mx, Some my ->
      let n = Array.length xs in
      if n < 2 then None
      else
        let s = ref 0.0 in
        for i = 0 to n - 1 do
          s := !s +. ((xs.(i) -. mx) *. (ys.(i) -. my))
        done;
        Some (!s /. float_of_int (n - 1))
  | _ -> None

let weighted_covariance_population xs ys ws =
  match (weighted_mean_array xs ws, weighted_mean_array ys ws) with
  | Some mx, Some my ->
      let total_w = sum_array ws in
      let s = ref 0.0 in
      for i = 0 to Array.length xs - 1 do
        s := !s +. (ws.(i) *. (xs.(i) -. mx) *. (ys.(i) -. my))
      done;
      Some (!s /. total_w)
  | _ -> None

let weighted_central_moment xs ws order =
  match weighted_mean_array xs ws with
  | None -> None
  | Some m ->
      let total_w = sum_array ws in
      let s = ref 0.0 in
      for i = 0 to Array.length xs - 1 do
        s := !s +. (ws.(i) *. (Float.pow (xs.(i) -. m) order))
      done;
      Some (!s /. total_w)

let quantile_array xs p =
  let n = Array.length xs in
  if n = 0 then None
  else
    let sorted = Array.copy xs in
    Array.sort compare sorted;
    let h = p *. float_of_int (n - 1) in
    let lo = int_of_float (Float.floor h) in
    let hi = min (lo + 1) (n - 1) in
    let frac = h -. float_of_int lo in
    Some (sorted.(lo) +. frac *. (sorted.(hi) -. sorted.(lo)))

let weighted_quantile_array xs ws p =
  let (xs, ws) = filter_positive_weights xs ws in
  let n = Array.length xs in
  if n = 0 then None
  else if n = 1 then Some xs.(0)
  else
    let pairs =
      Array.init n (fun i -> (xs.(i), ws.(i)))
      |> Array.to_list
      |> List.sort (fun (x1, _) (x2, _) -> compare x1 x2)
      |> Array.of_list
    in
    let total_w =
      Array.fold_left (fun acc (_, w) -> acc +. w) 0.0 pairs
    in
    if total_w <= 0.0 then None
    else
      let q_points = Array.make n 0.0 in
      let sorted_xs = Array.make n 0.0 in
      let cumulative = ref 0.0 in
      for i = 0 to n - 1 do
        let x, w = pairs.(i) in
        sorted_xs.(i) <- x;
        cumulative := !cumulative +. w;
        q_points.(i) <- (!cumulative -. (0.5 *. w)) /. total_w
      done;
      if p <= q_points.(0) then Some sorted_xs.(0)
      else if p >= q_points.(n - 1) then Some sorted_xs.(n - 1)
      else
        let rec find_interval i =
          if i >= n - 1 then sorted_xs.(n - 1)
          else if p <= q_points.(i + 1) then
            let left_q = q_points.(i) in
            let right_q = q_points.(i + 1) in
            if right_q <= left_q then sorted_xs.(i + 1)
            else
              let frac = (p -. left_q) /. (right_q -. left_q) in
              sorted_xs.(i)
              +. (frac *. (sorted_xs.(i + 1) -. sorted_xs.(i)))
          else find_interval (i + 1)
        in
        Some (find_interval 0)

(** Solve a linear system Ax = b using Gaussian elimination with partial pivoting.
    Returns the solution x and the inverse of A. *)
let solve_and_invert a b =
  let p = Array.length a in
  let aug = Array.init p (fun i ->
    Array.init (2 * p + 1) (fun j ->
      if j < p then a.(i).(j)
      else if j < 2 * p then (if j - p = i then 1.0 else 0.0)
      else b.(i)
    )
  ) in
  for col = 0 to p - 1 do
    let max_row = ref col in
    let max_val = ref (Float.abs aug.(col).(col)) in
    for row = col + 1 to p - 1 do
      let v = Float.abs aug.(row).(col) in
      if v > !max_val then begin max_val := v; max_row := row end
    done;
    if !max_val < 1e-14 then ()
    else begin
      if !max_row <> col then (let tmp = aug.(col) in aug.(col) <- aug.(!max_row); aug.(!max_row) <- tmp);
      let pivot = aug.(col).(col) in
      for row = col + 1 to p - 1 do
        let factor = aug.(row).(col) /. pivot in
        for j = col to 2 * p do aug.(row).(j) <- aug.(row).(j) -. factor *. aug.(col).(j) done
      done
    end
  done;
  let singular = ref false in
  for i = 0 to p - 1 do if Float.abs aug.(i).(i) < 1e-14 then singular := true done;
  if !singular then None
  else begin
    for col = p - 1 downto 0 do
      let pivot = aug.(col).(col) in
      for j = col to 2 * p do aug.(col).(j) <- aug.(col).(j) /. pivot done;
      for row = 0 to col - 1 do
        let factor = aug.(row).(col) in
        for j = col to 2 * p do aug.(row).(j) <- aug.(row).(j) -. factor *. aug.(col).(j) done
      done
    done;
    let inv = Array.init p (fun i -> Array.init p (fun j -> aug.(i).(j + p))) in
    let x = Array.init p (fun i -> aug.(i).(2 * p)) in
    Some (x, inv)
  end

(** Matrix multiplication A (m x n) * B (n x k) *)
let mat_mul a b =
  let m = Array.length a in
  let n = Array.length a.(0) in
  let k = Array.length b.(0) in
  let res = Array.make_matrix m k 0.0 in
  for i = 0 to m - 1 do
    for j = 0 to k - 1 do
      for l = 0 to n - 1 do
        res.(i).(j) <- res.(i).(j) +. a.(i).(l) *. b.(l).(j)
      done
    done
  done;
  res

(** Matrix-vector multiplication A (m x n) * v (n) *)
let mat_vec_mul a v =
  let m = Array.length a in
  let n = Array.length a.(0) in
  let res = Array.make m 0.0 in
  for i = 0 to m - 1 do
    for j = 0 to n - 1 do
      res.(i) <- res.(i) +. a.(i).(j) *. v.(j)
    done
  done;
  res

(** Dot product of two vectors *)
let dot_product v1 v2 =
  let n = Array.length v1 in
  let res = ref 0.0 in
  for i = 0 to n - 1 do res := !res +. v1.(i) *. v2.(i) done;
  !res
