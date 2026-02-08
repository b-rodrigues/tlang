(* stats/lm — simple linear regression *)
(* Statistical model. Operates on a DataFrame with numeric columns. *)
(* Fits y = intercept + slope * x using ordinary least squares. *)
(* Returns a Dict with: intercept, slope, r_squared, residuals, n, response, predictor. *)
(* Requires at least 2 observations and non-zero predictor variance. *)
(* Explicit error on NA values or invalid inputs. *)
(*
 * Examples:
 *   df = read_csv("data.csv")
 *   model = lm(df, "y", "x")
 *   model.intercept   => Float (y-intercept)
 *   model.slope        => Float (regression slope)
 *   model.r_squared    => Float (coefficient of determination)
 *   model.residuals    => Vector of residual values
 *   model.n            => Int (number of observations)
 *)
