(* math/sqrt — square root *)
(* Pure numerical primitive. Works on scalars (Int, Float) and Vectors. *)
(* Returns Float. Errors on negative input or NA. *)
(*
 * Examples:
 *   sqrt(4)          => 2.
 *   sqrt(2.0)        => 1.41421356...
 *   sqrt(Vector[1, 4, 9]) => Vector[1., 2., 3.]
 *   sqrt(-1)         => Error(ValueError: "sqrt() is undefined for negative numbers")
 *   sqrt(NA)         => Error(TypeError: "sqrt() encountered NA value...")
 *)
