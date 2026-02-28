(* src/packages/stats/math_utils.ml *)

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
