open Ast

(*
--# Confidence Intervals for Model Coefficients
--#
--# Computes confidence intervals for model coefficients based on the Student's t distribution.
--#
--# @name conf_int
--# @param model :: Model The model object (e.g., from lm() or imported).
--# @param level :: Float Confidence level (default 0.95).
--# @return :: DataFrame Columns: `term`, `lower`, `upper`.
--# @example
--#   conf_int(model)
--#   conf_int(model, 0.99)
--# @family stats
--# @seealso coef, summary
--# @export
*)
let conf_int_impl args _env =
  match args with
  | [VError _ as e] -> e
  | _ ->
    let parse_args = match args with
      | [VDict p]            -> Ok (p, 0.95)
      | [VDict p; VFloat l]  -> Ok (p, l)
      | [VDict p; VInt i]    -> Ok (p, float_of_int i)
      | _ -> Error (Error.type_error "Function `conf_int` expects model or (model, level).")
    in
    match parse_args with
    | Error e -> e
    | Ok (model_pairs, level) ->
      if level <= 0.0 || level >= 1.0 then
        Error.type_error "Function `conf_int` level must be between 0 and 1 (e.g. 0.95)."
      else
        match List.assoc_opt "_tidy_df" model_pairs, List.assoc_opt "_model_data" model_pairs with
        | Some (VDataFrame tidy), Some (VDict model) ->
           let family = match List.assoc_opt "family" model with
             | Some (VString f) -> String.lowercase_ascii f
             | _ -> "gaussian"
           in
           let df_opt = match List.assoc_opt "df_residual" model with
             | Some (VInt i)   -> Some i
             | Some (VFloat f) -> Some (int_of_float f)
             | _ -> None
           in
           (* Use t-distribution only for Gaussian models with known df.
              Otherwise (GLMs like binomial/poisson), use normal approximation. *)
           let use_df = if family = "gaussian" then df_opt else None in
           let alpha  = 1.0 -. level in
           let crit = Stats.quantile (1.0 -. alpha /. 2.0) use_df in
           
           let terms  = Arrow_table.get_string_column tidy.arrow_table "term" in
           let ests   = Arrow_table.get_float_column  tidy.arrow_table "estimate" in
           let ses    = Arrow_table.get_float_column  tidy.arrow_table "std_error" in
           let n = Array.length terms in
           
           let lowers = Array.init n (fun i ->
             match ests.(i), ses.(i) with
             | Some e, Some se -> Some (e -. crit *. se)
             | _ -> None)
           in
           let uppers = Array.init n (fun i ->
             match ests.(i), ses.(i) with
             | Some e, Some se -> Some (e +. crit *. se)
             | _ -> None)
           in
           let columns = [
             ("term",  Arrow_table.StringColumn terms);
             ("lower", Arrow_table.FloatColumn  lowers);
             ("upper", Arrow_table.FloatColumn  uppers);
           ] in
           let table = Arrow_table.create columns n in
           VDataFrame { arrow_table = table; group_keys = [] }
        | _ -> Error.type_error "Function `conf_int` expects a model returned by `lm` or `glm`."

let register env =
  Env.add "conf_int"
    (make_builtin ~name:"conf_int" ~variadic:true 1 conf_int_impl)
    env
