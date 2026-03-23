(* src/packages/stats/df_residual.ml *)
open Ast

(** df_residual(model) — returns the residual degrees of freedom of the model. *)
(*
--# Residual Degrees of Freedom
--#
--# Returns the residual degrees of freedom of a model.
--#
--# @name df_residual
--# @param model :: Model The model object.
--# @return :: Int The residual degrees of freedom.
--# @example
--#   model = lm(mpg ~ wt, data = mtcars)
--#   df = df_residual(model)
--# @family stats
--# @export
*)
let register env =
  Env.add "df_residual"
    (make_builtin ~name:"df_residual" 1 (fun args _env ->
      match args with
      | [VDict pairs] ->
        let model_data = match List.assoc_opt "_model_data" pairs with
          | Some (VDict d) -> d
          | _ -> pairs
        in
        (match List.assoc_opt "df_residual" model_data with
         | Some (VInt i) -> VInt i
         | Some (VFloat f) -> VInt (int_of_float f)
         | _ -> Error.type_error "Function `df_residual` could not find 'df_residual' in model object.")
      | [VError _ as e] -> e
      | _ -> Error.type_error "Function `df_residual` expects a model (Dict)."
    )) env
