(* math/pow — power function (base^exponent) *)
(* Pure numerical primitive. Works on scalars (Int, Float) and Vectors. *)
(* Returns Float. When applied to a Vector, raises each element to the given power. *)
(* Errors on NA. *)
(*
 * Examples:
 *   pow(2, 3)       => 8.
 *   pow(4, 0.5)     => 2.
 *   pow(Vector[2, 3, 4], 2) => Vector[4., 9., 16.]
 *   pow(NA, 2)      => Error(TypeError: "pow() encountered NA value...")
 *)
