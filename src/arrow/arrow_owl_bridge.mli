(* src/arrow/arrow_owl_bridge.mli *)

(** Bridge between Arrow-backed tables and numeric (Owl-compatible) arrays.
    Extracts numeric columns from Arrow tables into float arrays for statistical computation. *)

type owl_view = {
  backing : Arrow_table.t;
  column : string;
  arr : float array;
}

type lm_result = {
  coefficients : float array;
  std_errors : float array;
  t_statistics : float array;
  p_values : float array;
  r_squared : float;
  adj_r_squared : float;
  sigma : float;
  f_statistic : float;
  f_p_value : float;
  df_model : int;
  df_residual : int;
  nobs : int;
  log_lik : float;
  aic : float;
  bic : float;
  deviance : float;
  residuals_arr : float array;
  fitted_values : float array;
  hat_values : float array;
  cooks_distance : float array;
  std_residuals : float array;
  vcov : float array array;
  term_names : string list;
}

(** Extract a numeric column from an Arrow table as a float array.
    Converts Int64 columns to float, passes Float64 through directly.
    Returns [None] if the column doesn't exist, contains non-numeric data, or has NA values. *)
val numeric_column_to_owl : Arrow_table.t -> string -> owl_view option

(** Extract a numeric column, returning an error message on failure instead of [None]. *)
val numeric_column_to_owl_exn : Arrow_table.t -> string -> (owl_view, string) result

(** Compute the mean of a float array.
    Returns 0.0 for empty arrays. *)
val arr_mean : float array -> float

(** Compute simple linear regression (OLS) on two float arrays.
    Returns (intercept, slope, r_squared) or [None] if computation fails. *)
val linreg : float array -> float array -> (float * float * float) option

(** Compute residuals from a linear model *)
val residuals : float array -> float array -> float -> float -> float array

(** Compute Pearson correlation coefficient between two float arrays.
    Returns [None] if arrays have different lengths, fewer than 2 elements,
    or either has zero variance. *)
val pearson_cor : float array -> float array -> float option

(** Check if a float array has zero variance. *)
val array_has_zero_variance : float array -> bool

(** Scan predictor lists to detect collinearity or zero-variance predictor columns.
    Returns [Some error_msg] detailing collinearity, or [None] if predictors are linearly independent. *)
val detect_collinearity : (string * float array) list -> string option

(** Multi-predictor OLS/WLS regression.
    @param weights optional observation weights
    @param xs_list predictor arrays (each length n)
    @param ys response array (length n)
    @param predictor_names names of predictor columns
    @return [Some lm_result] or [None] if singular or inputs are invalid (e.g. mismatched lengths). *)
val linreg_multi :
  ?weights:float array ->
  float array list ->
  float array ->
  string list ->
  lm_result option
