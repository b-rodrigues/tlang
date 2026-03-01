(* src/packages/stats/sigma.ml *)
open Ast

(** sigma(model) — returns the residual standard deviation (sigma) of a linear model. *)
(*
--# Residual Standard Deviation
--#
--# Returns the residual standard deviation (sigma) of a linear model.
--# For GLMs, use `dispersion()` instead.
--#
--# @name sigma
--# @param model :: Model The model object.
--# @return :: Float The Residual Standard Error.
--#
--# @details
--# Sigma ($\hat{\sigma}$) represents the Residual Standard Error (RSE), which is an estimate
--# of the standard deviation of the error term $\epsilon$. It measures the "average"
--# distance that the observed values fall from the regression line.
--#
--# For OLS, it is calculated as = $\hat{\sigma} = \sqrt{\frac{\sum r_i^2}{n - p}}$, where
--# $n$ is the number of observations and $p$ is the number of estimated parameters.
--#
--# @example
--#   model = lm(mpg ~ wt, data = mtcars)
--#   s = sigma(model)
--# @family stats
--# @seealso dispersion
--# @export
*)
let register env =
  Env.add "sigma"
    (make_builtin ~name:"sigma" 1 (fun args _env ->
      match args with
      | [VDict pairs] ->
        let model_data = match List.assoc_opt "_model_data" pairs with
          | Some (VDict d) -> d
          | _ -> pairs
        in
        (match List.assoc_opt "sigma" model_data with
         | Some (VFloat f) -> VFloat f
         | Some (VInt i) -> VFloat (float_of_int i)
         | _ -> 
           if List.mem_assoc "dispersion" model_data then
             Error.type_error "Function `sigma` not applicable for this model. Use `dispersion()` instead."
           else
             Error.type_error "Function `sigma` could not find 'sigma' in model object.")
      | [VError _ as e] -> e
      | _ -> Error.type_error "Function `sigma` expects a model (Dict)."
    )) env
