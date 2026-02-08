(* stats/quantile — quantile at a given probability *)
(* Statistical summary. Operates on numeric Lists or Vectors. *)
(* Uses linear interpolation between data points. *)
(* Second argument is a probability p in [0, 1]. *)
(* Returns Float. Explicit error on NA or invalid inputs. *)
(*
 * Examples:
 *   quantile([1, 2, 3, 4, 5], 0.5)  => 3. (median)
 *   quantile([1, 2, 3, 4, 5], 0.0)  => 1. (min)
 *   quantile([1, 2, 3, 4, 5], 1.0)  => 5. (max)
 *   quantile([1, 2, 3, 4, 5], 0.25) => 2. (Q1)
 *   quantile([], 0.5)               => Error(ValueError: "quantile() called on empty data")
 *)
