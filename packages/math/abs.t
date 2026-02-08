(* math/abs — absolute value *)
(* Pure numerical primitive. Works on scalars (Int, Float) and Vectors. *)
(* Preserves type: abs(Int) => Int, abs(Float) => Float. *)
(* Errors on NA. *)
(*
 * Examples:
 *   abs(-5)       => 5
 *   abs(-3.14)    => 3.14
 *   abs(Vector[-1, 2, -3]) => Vector[1, 2, 3]
 *   abs(NA)       => Error(TypeError: "abs() encountered NA value...")
 *)
