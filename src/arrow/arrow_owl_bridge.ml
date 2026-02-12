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

(* ================================================================== *)
(* Multi-predictor OLS via Normal Equations                            *)
(* ================================================================== *)

(** Result type for multi-predictor linear regression *)
type lm_result = {
  coefficients : float array;     (* length p: intercept, then predictor slopes *)
  std_errors : float array;       (* length p *)
  t_statistics : float array;     (* length p *)
  p_values : float array;         (* length p *)
  r_squared : float;
  adj_r_squared : float;
  sigma : float;                  (* residual standard error *)
  f_statistic : float;
  f_p_value : float;
  df_model : int;                 (* number of predictors, k *)
  df_residual : int;              (* n - p *)
  nobs : int;
  log_lik : float;
  aic : float;
  bic : float;
  deviance : float;               (* residual sum of squares *)
  residuals_arr : float array;    (* length n *)
  fitted_values : float array;    (* length n *)
  hat_values : float array;       (* length n: diagonal of hat matrix *)
  cooks_distance : float array;   (* length n *)
  std_residuals : float array;    (* length n *)
  term_names : string list;       (* "(Intercept)" :: predictor names *)
}

(* --- Matrix utilities (pure OCaml, no Owl dependency) --- *)

(** Solve a symmetric positive-definite system A x = b via Gaussian elimination
    with partial pivoting. Returns the solution x and the inverse of A.
    A is p×p, b is p-vector. Returns None if singular. *)
let solve_and_invert (a : float array array) (b : float array)
    : (float array * float array array) option =
  let p = Array.length a in
  (* Augmented matrix [A | I | b] of size p × (2p+1) *)
  let aug = Array.init p (fun i ->
    Array.init (2 * p + 1) (fun j ->
      if j < p then a.(i).(j)
      else if j < 2 * p then (if j - p = i then 1.0 else 0.0)
      else b.(i)
    )
  ) in
  (* Forward elimination with partial pivoting *)
  for col = 0 to p - 1 do
    (* Find pivot *)
    let max_row = ref col in
    let max_val = ref (Float.abs aug.(col).(col)) in
    for row = col + 1 to p - 1 do
      let v = Float.abs aug.(row).(col) in
      if v > !max_val then begin
        max_val := v;
        max_row := row
      end
    done;
    if !max_val < 1e-14 then begin
      (* Matrix is (nearly) singular — set diagonal to large value to signal *)
      aug.(col).(col) <- 0.0
    end else begin
      (* Swap rows *)
      if !max_row <> col then begin
        let tmp = aug.(col) in
        aug.(col) <- aug.(!max_row);
        aug.(!max_row) <- tmp
      end;
      (* Eliminate below *)
      let pivot = aug.(col).(col) in
      for row = col + 1 to p - 1 do
        let factor = aug.(row).(col) /. pivot in
        for j = col to 2 * p do
          aug.(row).(j) <- aug.(row).(j) -. factor *. aug.(col).(j)
        done
      done
    end
  done;
  (* Check for singularity *)
  let singular = ref false in
  for i = 0 to p - 1 do
    if Float.abs aug.(i).(i) < 1e-14 then singular := true
  done;
  if !singular then None
  else begin
    (* Back substitution for both inverse and solution *)
    for col = p - 1 downto 0 do
      let pivot = aug.(col).(col) in
      for j = col to 2 * p do
        aug.(col).(j) <- aug.(col).(j) /. pivot
      done;
      for row = 0 to col - 1 do
        let factor = aug.(row).(col) in
        for j = col to 2 * p do
          aug.(row).(j) <- aug.(row).(j) -. factor *. aug.(col).(j)
        done
      done
    done;
    (* Extract inverse and solution *)
    let inv = Array.init p (fun i ->
      Array.init p (fun j -> aug.(i).(j + p))
    ) in
    let x = Array.init p (fun i -> aug.(i).(2 * p)) in
    Some (x, inv)
  end

(* --- t-distribution p-value approximation --- *)

(** Log-gamma via Lanczos approximation *)
let rec log_gamma v =
  let g = 7.0 in
  let coefs = [| 0.99999999999980993; 676.5203681218851; -1259.1392167224028;
                 771.32342877765313; -176.61502916214059; 12.507343278686905;
                 -0.13857109526572012; 9.9843695780195716e-6; 1.5056327351493116e-7 |] in
  if v < 0.5 then
    let pi = Float.pi in
    log pi -. log (Float.abs (sin (pi *. v))) -. log_gamma (1.0 -. v)
  else begin
    let vv = v -. 1.0 in
    let x = ref coefs.(0) in
    for i = 1 to 8 do
      x := !x +. coefs.(i) /. (vv +. float_of_int i)
    done;
    let t = vv +. g +. 0.5 in
    0.5 *. log (2.0 *. Float.pi) +. (vv +. 0.5) *. log t -. t +. log !x
  end

(** Regularised incomplete beta function I_x(a, b) via continued fraction.
    Used to compute CDF of t, F distributions. *)
let betai x a b =
  if x <= 0.0 then 0.0
  else if x >= 1.0 then 1.0
  else begin
    (* Lentz's continued fraction for I_x(a,b) *)
    let max_iter = 200 in
    let eps = 3.0e-12 in
    let fpmin = 1.0e-30 in
    (* When x < (a+1)/(a+b+2), use I_x directly; otherwise use 1 - I_{1-x}(b,a) *)
    let use_symmetry = x >= (a +. 1.0) /. (a +. b +. 2.0) in
    let (xx, aa, bb) = if use_symmetry then (1.0 -. x, b, a) else (x, a, b) in
    let qab = aa +. bb in
    let qap = aa +. 1.0 in
    let qam = aa -. 1.0 in
    let c = ref 1.0 in
    let d = ref (1.0 -. qab *. xx /. qap) in
    if Float.abs !d < fpmin then d := fpmin;
    d := 1.0 /. !d;
    let h = ref !d in
    let converged = ref false in
    let m = ref 1 in
    while !m <= max_iter && not !converged do
      let mf = float_of_int !m in
      (* Even step *)
      let d1 = mf *. (bb -. mf) *. xx /. ((qam +. 2.0 *. mf) *. (aa +. 2.0 *. mf)) in
      d := 1.0 +. d1 *. !d;
      if Float.abs !d < fpmin then d := fpmin;
      c := 1.0 +. d1 /. !c;
      if Float.abs !c < fpmin then c := fpmin;
      d := 1.0 /. !d;
      h := !h *. !d *. !c;
      (* Odd step *)
      let d2 = -.(aa +. mf) *. (qab +. mf) *. xx /. ((aa +. 2.0 *. mf) *. (qap +. 2.0 *. mf)) in
      d := 1.0 +. d2 *. !d;
      if Float.abs !d < fpmin then d := fpmin;
      c := 1.0 +. d2 /. !c;
      if Float.abs !c < fpmin then c := fpmin;
      d := 1.0 /. !d;
      let del = !d *. !c in
      h := !h *. del;
      if Float.abs (del -. 1.0) < eps then converged := true;
      incr m
    done;
    (* Front factor: x^a * (1-x)^b / (a * Beta(a,b)) *)
    let ln_front = aa *. log xx +. bb *. log (1.0 -. xx)
                   -. log aa
                   -. (log_gamma aa +. log_gamma bb -. log_gamma (aa +. bb)) in
    let front = exp ln_front in
    let result = front *. !h in
    if use_symmetry then 1.0 -. result else result
  end

(** Two-tailed p-value from t-distribution with df degrees of freedom *)
let t_pvalue t_stat df =
  let x = df /. (df +. t_stat *. t_stat) in
  let p = betai x (df /. 2.0) 0.5 in
  p  (* This is already the two-tailed p-value *)

(** p-value from F-distribution: P(F > f_stat) with df1, df2 degrees of freedom *)
let f_pvalue f_stat df1 df2 =
  if f_stat <= 0.0 then 1.0
  else
    let x = df2 /. (df2 +. float_of_int df1 *. f_stat) in
    betai x (df2 /. 2.0) (float_of_int df1 /. 2.0)

(** Multi-predictor OLS regression.
    xs: list of predictor arrays (each length n)
    ys: response array (length n)
    predictor_names: names of predictor columns
    Returns None if system is singular or inputs invalid. *)
let linreg_multi (xs_list : float array list) (ys : float array)
    (predictor_names : string list) : lm_result option =
  let n = Array.length ys in
  let k = List.length xs_list in  (* number of predictors *)
  let p = k + 1 in  (* total parameters including intercept *)
  if n < p || n < 2 then None
  else begin
    (* Build design matrix X (n × p): column 0 = intercept (all 1s) *)
    let xs_arr = Array.of_list xs_list in
    let x_matrix = Array.init n (fun i ->
      Array.init p (fun j ->
        if j = 0 then 1.0 else xs_arr.(j - 1).(i)
      )
    ) in
    (* Compute X'X (p × p) *)
    let xtx = Array.init p (fun i ->
      Array.init p (fun j ->
        let s = ref 0.0 in
        for row = 0 to n - 1 do
          s := !s +. x_matrix.(row).(i) *. x_matrix.(row).(j)
        done;
        !s
      )
    ) in
    (* Compute X'y (p-vector) *)
    let xty = Array.init p (fun j ->
      let s = ref 0.0 in
      for row = 0 to n - 1 do
        s := !s +. x_matrix.(row).(j) *. ys.(row)
      done;
      !s
    ) in
    (* Solve (X'X) β = X'y and get (X'X)^{-1} *)
    match solve_and_invert xtx xty with
    | None -> None
    | Some (beta, xtx_inv) ->
      (* Fitted values and residuals *)
      let fitted = Array.init n (fun i ->
        let s = ref 0.0 in
        for j = 0 to p - 1 do
          s := !s +. x_matrix.(i).(j) *. beta.(j)
        done;
        !s
      ) in
      let resid = Array.init n (fun i -> ys.(i) -. fitted.(i)) in
      (* SS_res, SS_tot *)
      let nf = float_of_int n in
      let mean_y = Array.fold_left ( +. ) 0.0 ys /. nf in
      let ss_res = Array.fold_left (fun acc r -> acc +. r *. r) 0.0 resid in
      let ss_tot = Array.fold_left (fun acc y -> acc +. (y -. mean_y) *. (y -. mean_y)) 0.0 ys in
      let df_resid = n - p in
      let dff = float_of_int df_resid in
      let sigma2 = if df_resid > 0 then ss_res /. dff else 0.0 in
      let sigma = sqrt sigma2 in
      (* R² and adjusted R² *)
      let r_sq = if ss_tot = 0.0 then 1.0 else 1.0 -. ss_res /. ss_tot in
      let adj_r_sq = if ss_tot = 0.0 || df_resid = 0 then r_sq
                     else 1.0 -. (1.0 -. r_sq) *. (nf -. 1.0) /. dff in
      (* Standard errors, t-statistics, p-values *)
      let std_errs = Array.init p (fun j ->
        if sigma2 > 0.0 && xtx_inv.(j).(j) >= 0.0
        then sqrt (sigma2 *. xtx_inv.(j).(j))
        else 0.0
      ) in
      let t_stats = Array.init p (fun j ->
        if std_errs.(j) > 0.0 then beta.(j) /. std_errs.(j) else 0.0
      ) in
      let p_vals = Array.init p (fun j ->
        if df_resid > 0 && std_errs.(j) > 0.0
        then t_pvalue t_stats.(j) dff
        else 1.0
      ) in
      (* F-statistic *)
      let ss_model = ss_tot -. ss_res in
      let f_stat = if k > 0 && df_resid > 0 && ss_res > 0.0
                   then (ss_model /. float_of_int k) /. (ss_res /. dff)
                   else 0.0 in
      let f_pval = if k > 0 && df_resid > 0
                   then f_pvalue f_stat k (float_of_int df_resid)
                   else 1.0 in
      (* Hat matrix diagonal: h_ii = x_i' (X'X)^{-1} x_i *)
      let hat_vals = Array.init n (fun i ->
        let h = ref 0.0 in
        for j1 = 0 to p - 1 do
          for j2 = 0 to p - 1 do
            h := !h +. x_matrix.(i).(j1) *. xtx_inv.(j1).(j2) *. x_matrix.(i).(j2)
          done
        done;
        !h
      ) in
      (* Cook's distance and standardised residuals *)
      let pf = float_of_int p in
      let cooks_d = Array.init n (fun i ->
        let hi = hat_vals.(i) in
        let denom = pf *. sigma2 *. (1.0 -. hi) *. (1.0 -. hi) in
        if denom > 0.0 then resid.(i) *. resid.(i) *. hi /. denom else 0.0
      ) in
      let std_resid = Array.init n (fun i ->
        let hi = hat_vals.(i) in
        let denom = sigma *. sqrt (1.0 -. hi) in
        if denom > 0.0 then resid.(i) /. denom else 0.0
      ) in
      (* Leave-one-out sigma estimates *)
      (* Log-likelihood, AIC, BIC *)
      let log_lik = -. nf /. 2.0 *. (1.0 +. log (2.0 *. Float.pi) +. log (ss_res /. nf)) in
      let aic = -2.0 *. log_lik +. 2.0 *. (pf +. 1.0) in (* +1 for sigma *)
      let bic = -2.0 *. log_lik +. (pf +. 1.0) *. log nf in
      let term_names = "(Intercept)" :: predictor_names in
      Some {
        coefficients = beta;
        std_errors = std_errs;
        t_statistics = t_stats;
        p_values = p_vals;
        r_squared = r_sq;
        adj_r_squared = adj_r_sq;
        sigma;
        f_statistic = f_stat;
        f_p_value = f_pval;
        df_model = k;
        df_residual = df_resid;
        nobs = n;
        log_lik;
        aic;
        bic;
        deviance = ss_res;
        residuals_arr = resid;
        fitted_values = fitted;
        hat_values = hat_vals;
        cooks_distance = cooks_d;
        std_residuals = std_resid;
        term_names;
      }
  end
