(* stats/sd — sample standard deviation *)
(* Statistical summary. Operates on numeric Lists or Vectors. *)
(* Uses Bessel's correction (n-1 denominator). *)
(* Returns Float. Requires at least 2 values. Explicit error on NA. *)
(*
 * Examples:
 *   sd([2, 4, 4, 4, 5, 5, 7, 9]) => ~2.138
 *   sd([1])                        => Error(ValueError: "sd() requires at least 2 values")
 *   sd([1, NA, 3])                 => Error(TypeError: "sd() encountered NA value...")
 *)
