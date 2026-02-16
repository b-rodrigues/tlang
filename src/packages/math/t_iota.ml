open Ast

(*
--# Create a vector of ones
--#
--# Creates a vector of length n filled with 1.0.
--# Use with `seq` or `ndarray` for more complex interactions.
--#
--# @name iota
--# @param n :: Int The length of the vector.
--# @return :: Vector[Float] A vector of ones.
--# @example
--#   iota(3)
--#   -- Returns: [1.0, 1.0, 1.0]
--# @family math
--# @seealso seq, ndarray
--# @export
*)
let register env =
  Env.add "iota"
    (make_builtin ~name:"iota" 1 (fun args _env ->
      match args with
      | [VInt n] ->
          if n < 0 then Error.value_error "iota expects a non-negative integer."
          else
            let arr = Array.make n (VFloat 1.0) in
            VVector arr
      | _ -> Error.type_error "iota expects a single Integer argument."
    ))
    env
