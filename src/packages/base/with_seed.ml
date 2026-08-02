open Ast

(*
--# Run a thunk with a scoped random seed
--#
--# Sets the global random number generator to `seed` for the duration of the
--# thunk evaluation, then restores the previous RNG state. This scopes
--# determinism to a single expression: any random draws outside the thunk are
--# unaffected. Useful for reproducible property tests and sampling.
--#
--# The thunk is a one-parameter lambda (the argument is ignored) so that it
--# binds lazily, mirroring prop_for_all's predicate convention:
--#
--#   with_seed(42, \(x) sample([1, 2, 3, 4, 5], n = 3))
--#
--# @name with_seed
--# @param seed :: Int The seed value to scope the RNG to.
--# @param thunk :: Function A one-parameter lambda whose body is run under `seed`.
--# @return :: Any The result of evaluating `thunk`.
--# @example
--#   with_seed(42, \(x) sample([1, 2, 3, 4, 5], n = 3))
--# @family base
--# @seealso set_seed, sample, slice_sample, prop_for_all
--# @export
*)
let register ~eval_call env =
  Env.add "with_seed"
    (make_builtin ~name:"with_seed" 2 (fun args _env ->
       match args with
       | [VInt seed; (VLambda _ | VBuiltin _) as fn] ->
           Rng.with_seed seed (fun () ->
               eval_call env fn [ (None, Ast.mk_expr (Value (VNA NAGeneric))) ])
       | [VInt _; other] ->
           Error.type_error
             (Printf.sprintf
                "Function `with_seed` expects a lambda or builtin as second argument, got %s."
                (Ast.Utils.type_name other))
       | [VNA _; _] ->
           Error.type_error "Function `with_seed` expects an integer seed.\nReceived NA."
       | [_; _] ->
           Error.type_error "Function `with_seed` expects an integer seed."
       | _ -> Error.arity_error_named "with_seed" 2 (List.length args)))
    env
