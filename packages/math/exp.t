(* math/exp — exponential function (e^x) *)
(* Pure numerical primitive. Works on scalars (Int, Float) and Vectors. *)
(* Returns Float. Errors on NA. *)
(*
 * Examples:
 *   exp(0)          => 1.
 *   exp(1)          => 2.71828...
 *   exp(Vector[0, 1]) => Vector[1., 2.71828...]
 *   exp(NA)         => Error(TypeError: "exp() encountered NA value...")
 *)
