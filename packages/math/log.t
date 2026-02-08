(* math/log — natural logarithm *)
(* Pure numerical primitive. Works on scalars (Int, Float) and Vectors. *)
(* Returns Float. Errors on non-positive input or NA. *)
(*
 * Examples:
 *   log(1)          => 0.
 *   log(2.71828)    => ~1.
 *   log(Vector[1, 10]) => Vector[0., 2.302...]
 *   log(0)          => Error(ValueError: "log() is undefined for non-positive numbers")
 *   log(-1)         => Error(ValueError: "log() is undefined for non-positive numbers")
 *   log(NA)         => Error(TypeError: "log() encountered NA value...")
 *)
