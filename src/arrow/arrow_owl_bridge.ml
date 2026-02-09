(* src/arrow/arrow_owl_bridge.ml *)
(* Bridge between Arrow-backed tables and numeric (Owl-compatible) arrays. *)
(* Extracts numeric columns from Arrow tables into float arrays that can   *)
(* be used directly for statistical computation or wrapped in Owl arrays.  *)
(*                                                                         *)
(* When Owl is available as a dependency, the float arrays returned here   *)
(* can be converted to Owl.Arr.t via Owl.Arr.of_array for zero-copy       *)
(* matrix operations (linear algebra, regression, etc).                    *)

(** A numeric view over a column in an Arrow table.
    Keeps a reference to the backing table to prevent GC collection
    of the underlying Arrow buffers (important for zero-copy access). *)
type owl_view = {
  backing : Arrow_table.t;
  column : string;
  arr : float array;
}

(** Extract a numeric column from an Arrow table as a float array.
    Converts Int64 columns to float, passes Float64 through directly.
    Returns None if the column doesn't exist or contains non-numeric data.
    NA values in the column cause the extraction to fail (returns None)
    because numeric computation requires complete data. *)
let numeric_column_to_owl (table : Arrow_table.t) (col_name : string) : owl_view option =
  match Arrow_table.get_column table col_name with
  | None -> None
  | Some col ->
    match Arrow_table.column_type_of col with
    | Arrow_table.ArrowFloat64 ->
      (match col with
       | Arrow_table.FloatColumn a ->
         let n = Array.length a in
         let result = Array.make n 0.0 in
         let has_na = ref false in
         for i = 0 to n - 1 do
           match a.(i) with
           | Some f -> result.(i) <- f
           | None -> has_na := true
         done;
         if !has_na then None
         else Some { backing = table; column = col_name; arr = result }
       | _ -> None)
    | Arrow_table.ArrowInt64 ->
      (match col with
       | Arrow_table.IntColumn a ->
         let n = Array.length a in
         let result = Array.make n 0.0 in
         let has_na = ref false in
         for i = 0 to n - 1 do
           match a.(i) with
           | Some int_val -> result.(i) <- float_of_int int_val
           | None -> has_na := true
         done;
         if !has_na then None
         else Some { backing = table; column = col_name; arr = result }
       | _ -> None)
    | _ -> None

(** Extract a numeric column, returning an error message on failure
    instead of None. Useful for providing informative error messages
    in statistical functions. *)
let numeric_column_to_owl_exn (table : Arrow_table.t) (col_name : string)
    : (owl_view, string) result =
  match Arrow_table.get_column table col_name with
  | None -> Error (Printf.sprintf "Column '%s' not found" col_name)
  | Some col ->
    match Arrow_table.column_type_of col with
    | Arrow_table.ArrowFloat64 | Arrow_table.ArrowInt64 ->
      (match numeric_column_to_owl table col_name with
       | Some view -> Ok view
       | None -> Error (Printf.sprintf "Column '%s' contains NA values" col_name))
    | typ ->
      Error (Printf.sprintf "Column '%s' has non-numeric type %s"
               col_name (Arrow_table.arrow_type_to_string typ))

(** Compute the mean of a float array.
    Returns 0.0 for empty arrays (caller should check length first). *)
let arr_mean (a : float array) : float =
  let n = Array.length a in
  if n = 0 then 0.0
  else Array.fold_left ( +. ) 0.0 a /. float_of_int n

(** Compute simple linear regression (OLS) on two float arrays.
    Returns (intercept, slope, r_squared) or None if computation fails. *)
let linreg (xs : float array) (ys : float array) : (float * float * float) option =
  let n = Array.length xs in
  if n <> Array.length ys || n < 2 then None
  else
    let nf = float_of_int n in
    let mean_x = Array.fold_left ( +. ) 0.0 xs /. nf in
    let mean_y = Array.fold_left ( +. ) 0.0 ys /. nf in
    let sum_xy = ref 0.0 in
    let sum_xx = ref 0.0 in
    for i = 0 to n - 1 do
      let dx = xs.(i) -. mean_x in
      sum_xy := !sum_xy +. dx *. (ys.(i) -. mean_y);
      sum_xx := !sum_xx +. dx *. dx
    done;
    if !sum_xx = 0.0 then None
    else begin
      let slope = !sum_xy /. !sum_xx in
      let intercept = mean_y -. slope *. mean_x in
      let ss_res = ref 0.0 in
      let ss_tot = ref 0.0 in
      for i = 0 to n - 1 do
        let fitted = intercept +. slope *. xs.(i) in
        let r = ys.(i) -. fitted in
        ss_res := !ss_res +. r *. r;
        ss_tot := !ss_tot +. (ys.(i) -. mean_y) *. (ys.(i) -. mean_y)
      done;
      let r_squared = if !ss_tot = 0.0 then 1.0 else 1.0 -. !ss_res /. !ss_tot in
      Some (intercept, slope, r_squared)
    end

(** Compute residuals from a linear model *)
let residuals (xs : float array) (ys : float array) (intercept : float) (slope : float) : float array =
  Array.init (Array.length xs) (fun i ->
    ys.(i) -. (intercept +. slope *. xs.(i)))

(** Compute Pearson correlation coefficient between two float arrays.
    Returns None if arrays have different lengths, fewer than 2 elements,
    or either has zero variance. *)
let pearson_cor (xs : float array) (ys : float array) : float option =
  let n = Array.length xs in
  if n <> Array.length ys || n < 2 then None
  else
    let nf = float_of_int n in
    let mean_x = Array.fold_left ( +. ) 0.0 xs /. nf in
    let mean_y = Array.fold_left ( +. ) 0.0 ys /. nf in
    let sum_xy = ref 0.0 in
    let sum_xx = ref 0.0 in
    let sum_yy = ref 0.0 in
    for i = 0 to n - 1 do
      let dx = xs.(i) -. mean_x in
      let dy = ys.(i) -. mean_y in
      sum_xy := !sum_xy +. dx *. dy;
      sum_xx := !sum_xx +. dx *. dx;
      sum_yy := !sum_yy +. dy *. dy
    done;
    if !sum_xx = 0.0 || !sum_yy = 0.0 then None
    else Some (!sum_xy /. Float.sqrt (!sum_xx *. !sum_yy))
