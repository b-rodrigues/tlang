(* src/packages/stats/deviance.ml *)
open Ast

(** deviance(model) — returns the deviance of the model. *)
(*
--# Model Deviance
--#
--# Returns the deviance of a model.
--#
--# @name deviance
--# @param model :: Model The model object.
--# @return :: Float The deviance.
--# @example
--#   model = lm(mpg ~ wt, data = mtcars)
--#   dev = deviance(model)
--# @family stats
--# @export
*)
let register env =
  Env.add "deviance"
    (make_builtin ~name:"deviance" 1 (fun args _env ->
      match args with
      | [VDict pairs] ->
        let model_data = match List.assoc_opt "_model_data" pairs with
          | Some (VDict d) -> d
          | _ -> pairs
        in
        (match List.assoc_opt "deviance" model_data with
         | Some (VFloat f) -> VFloat f
         | Some (VInt i) -> VFloat (float_of_int i)
         | _ -> Error.type_error "Function `deviance` could not find 'deviance' in model object.")
      | [VError _ as e] -> e
      | _ -> Error.type_error "Function `deviance` expects a model (Dict)."
    )) env
