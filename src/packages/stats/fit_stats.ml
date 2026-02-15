open Ast

(** fit_stats(model) — returns a 1-row DataFrame of model-level statistics.
    Equivalent to broom::glance(). *)
(*
--# Model Fit Statistics
--#
--# Returns a one-row DataFrame containing model-level statistics (R-squared, AIC, etc.).
--#
--# @name fit_stats
--# @param model :: Model The model object.
--# @return :: DataFrame Model statistics.
--# @example
--#   fit_stats(model)
--# @family stats
--# @seealso lm, summary
--# @export
*)
let register env =
  Env.add "fit_stats"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDict pairs] ->
        (match List.assoc_opt "_model_data" pairs with
         | Some (VDict model) ->
           let get_float key = match List.assoc_opt key model with
             | Some (VFloat f) -> Some f | _ -> None in
           let get_int key = match List.assoc_opt key model with
             | Some (VInt i) -> Some i | _ -> None in
           (* Build 1-row DataFrame *)
           let mk_f v = match v with Some f -> Some f | None -> None in
           let mk_i v = match v with Some i -> Some (float_of_int i) | None -> None in
           let columns = [
             ("r_squared",     Arrow_table.FloatColumn [| mk_f (get_float "r_squared") |]);
             ("adj_r_squared", Arrow_table.FloatColumn [| mk_f (get_float "adj_r_squared") |]);
             ("sigma",         Arrow_table.FloatColumn [| mk_f (get_float "sigma") |]);
             ("statistic",     Arrow_table.FloatColumn [| mk_f (get_float "f_statistic") |]);
             ("p_value",       Arrow_table.FloatColumn [| mk_f (get_float "f_p_value") |]);
             ("df",            Arrow_table.FloatColumn [| mk_i (get_int "df_model") |]);
             ("logLik",        Arrow_table.FloatColumn [| mk_f (get_float "log_lik") |]);
             ("AIC",           Arrow_table.FloatColumn [| mk_f (get_float "aic") |]);
             ("BIC",           Arrow_table.FloatColumn [| mk_f (get_float "bic") |]);
             ("deviance",      Arrow_table.FloatColumn [| mk_f (get_float "deviance") |]);
             ("df_residual",   Arrow_table.FloatColumn [| mk_i (get_int "df_residual") |]);
             ("nobs",          Arrow_table.FloatColumn [| mk_i (get_int "nobs") |]);
           ] in
           let table = Arrow_table.create columns 1 in
           VDataFrame { arrow_table = table; group_keys = [] }
         | _ ->
           Error.type_error "Function `fit_stats` expects a model returned by `lm`.")
      | _ ->
        Error.type_error "Function `fit_stats` expects a model returned by `lm`."
    ))
    env
