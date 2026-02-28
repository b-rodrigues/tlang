open Ast

(*
--# Model Coefficients
--#
--# Extracts the coefficient estimates from a model object, keyed by term name.
--#
--# @name coef
--# @param model :: Model The model object (e.g., from lm() or imported).
--# @return :: DataFrame Coefficient estimates with columns `term` and `estimate`.
--# @example
--#   coef(model)
--# @family stats
--# @seealso summary, conf_int
--# @export
*)
let register env =
  Env.add "coef"
    (make_builtin ~name:"coef" 1 (fun args _env ->
      match args with
      | [VDict pairs] ->
        (match List.assoc_opt "_tidy_df" pairs with
         | Some (VDataFrame tidy) ->
           (* Extract term and estimate columns from the existing tidy DataFrame *)
           let terms     = Arrow_table.get_string_column tidy.arrow_table "term" in
           let estimates = Arrow_table.get_float_column  tidy.arrow_table "estimate" in
           let columns = [
             ("term",     Arrow_table.StringColumn terms);
             ("estimate", Arrow_table.FloatColumn  estimates);
           ] in
           let n = Array.length terms in
           let table = Arrow_table.create columns n in
           VDataFrame { arrow_table = table; group_keys = [] }
         | _ ->
           Error.type_error "Function `coef` expects a model with tidy coefficients.")
      | [VError _ as e] -> e
      | _ ->
        Error.type_error "Function `coef` expects a model returned by `lm` or `glm`."
    ))
    env
