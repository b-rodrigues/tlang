open Ast

(*
--# Set random seed for reproducibility
--#
--# Initializes the global random number generator with a given seed, making
--# subsequent calls to sample() and slice_sample() deterministic.
--#
--# @name set_seed
--# @param seed :: Int The seed value.
--# @return :: NA
--# @example
--#   set_seed(42)
--#   sample([1, 2, 3, 4, 5], n = 3)
--# @family base
--# @seealso sample, slice_sample
--# @export
*)
let register env =
  Env.add "set_seed"
    (make_builtin ~name:"set_seed" 1 (fun args _env ->
      match args with
      | [VInt seed] -> Rng.set_seed seed; VNA NAGeneric
      | [_] -> Error.type_error "Function `set_seed` expects an integer seed."
      | _ -> Error.arity_error_named "set_seed" 1 (List.length args)
    ))
    env
