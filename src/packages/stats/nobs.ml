(* src/packages/stats/nobs.ml *)
open Ast

(** nobs(model) — returns the number of observations used to fit the model. *)
(*
--# Number of Observations
--#
--# Returns the number of observations used to fit a model.
--#
--# @name nobs
--# @param model :: Model The model object.
--# @return :: Int The number of observations.
--# @example
--#   model = lm(mpg ~ wt, data: mtcars)
--#   n = nobs(model)
--# @family stats
--# @export
*)
let register env =
  Env.add "nobs"
    (make_builtin ~name:"nobs" 1 (fun args _env ->
      match args with
      | [VDict pairs] ->
        let model_data = match List.assoc_opt "_model_data" pairs with
          | Some (VDict d) -> d
          | _ -> pairs
        in
        (match List.assoc_opt "nobs" model_data with
         | Some (VInt i) -> VInt i
         | Some (VFloat f) -> VInt (int_of_float f)
         | _ -> Error.type_error "Function `nobs` could not find 'nobs' in model object.")
      | [VError _ as e] -> e
      | _ -> Error.type_error "Function `nobs` expects a model (Dict)."
    )) env
