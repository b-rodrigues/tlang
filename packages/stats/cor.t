(* stats/cor — Pearson correlation coefficient *)
(* Statistical summary. Operates on two numeric Vectors or Lists of equal length. *)
(* Returns Float in [-1, 1]. Requires at least 2 values. *)
(* Explicit error on NA, mismatched lengths, or zero variance. *)
(*
 * Examples:
 *   cor(Vector[1, 2, 3], Vector[2, 4, 6])   => 1. (perfect positive)
 *   cor(Vector[1, 2, 3], Vector[3, 2, 1])   => -1. (perfect negative)
 *   cor(Vector[1, 1, 1], Vector[2, 4, 6])   => Error (zero variance)
 *)
