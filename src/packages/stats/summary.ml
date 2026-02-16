open Ast

(** summary(model) — returns the tidy coefficients DataFrame from an lm() model.
    Equivalent to broom::tidy(). *)
(*
--# Model Summary
--#
--# Returns a tidy DataFrame of regression coefficients and statistics.
--#
--# @name summary
--# @param model :: Model The model object (e.g., from lm()).
--# @return :: DataFrame Tidy summary of coefficients.
--# @example
--#   summary(model)
--# @family stats
--# @seealso lm, fit_stats
--# @export
*)
let register env =
  Env.add "summary"
    (make_builtin ~name:"summary" 1 (fun args _env ->
      match args with
      | [VDict pairs] ->
        (match List.assoc_opt "_tidy_df" pairs with
         | Some (VDataFrame _ as df) -> df
         | _ ->
           Error.type_error "Function `summary` expects a model returned by `lm`.")
      | _ ->
        Error.type_error "Function `summary` expects a model returned by `lm`."
    ))
    env
