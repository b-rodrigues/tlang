(* src/packages/stats/dispersion.ml *)
open Ast

(** dispersion(model) — returns the dispersion parameter of a GLM. *)
(*
--# Dispersion Parameter
--#
--# Returns the dispersion parameter of a Generalized Linear Model (GLM).
--# For linear models (lm), use `sigma()` instead.
--#
--# @name dispersion
--# @param model :: Model The model object.
--# @return :: Float The dispersion parameter.
--# @example
--#   model = glm(survived ~ age, data: df, family = "binomial")
--#   d = dispersion(model)
--# @family stats
--# @seealso sigma
--# @export
*)
let register env =
  Env.add "dispersion"
    (make_builtin ~name:"dispersion" 1 (fun args _env ->
      match args with
      | [VDict pairs] ->
        let model_data = match List.assoc_opt "_model_data" pairs with
          | Some (VDict d) -> d
          | _ -> pairs
        in
        (match List.assoc_opt "dispersion" model_data with
         | Some (VFloat f) -> VFloat f
         | Some (VInt i) -> VFloat (float_of_int i)
         | _ -> 
           if List.mem_assoc "sigma" model_data then
             Error.type_error "Function `dispersion` not applicable for this model. Use `sigma()` instead."
           else
             Error.type_error "Function `dispersion` could not find 'dispersion' in model object.")
      | [VError _ as e] -> e
      | _ -> Error.type_error "Function `dispersion` expects a model (Dict)."
    )) env
