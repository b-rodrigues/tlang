(* src/stats.ml *)
(* Statistical utility functions for distributions and quantiles. *)

(** Inverse CDF (Percent-point function) of the standard normal distribution.
    Uses a rational approximation (Beasley-Springer-Moro or similar). *)
external normal_quantile : float -> float = "caml_stats_normal_quantile"

(** Inverse CDF (Percent-point function) of Student's t distribution.
    p: cumulative probability (0 < p < 1), df: degrees of freedom (df > 0). *)
external t_quantile : float -> int -> float = "caml_stats_t_quantile"

(** Unified quantile function. Use t-distribution if df is provided, 
    otherwise fall back to normal distribution. *)
let quantile p df_opt =
  match df_opt with
  | Some df -> t_quantile p df
  | None -> normal_quantile p
