(* stats/mean — arithmetic mean *)
(* Statistical summary. Operates on numeric Lists or Vectors. *)
(* Returns Float. Explicit error on NA values or empty input. *)
(*
 * Examples:
 *   mean([1, 2, 3, 4, 5])  => 3.
 *   mean(Vector[10, 20])    => 15.
 *   mean([])                => Error(ValueError: "mean() called on empty list")
 *   mean([1, NA, 3])        => Error(TypeError: "mean() encountered NA value...")
 *)
