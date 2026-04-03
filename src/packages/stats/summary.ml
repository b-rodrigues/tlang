open Ast

(** summary(model) — returns a tidy summary DataFrame for native models.
    For regression models this is coefficient-level output; for tree/ensemble
    PMML models this falls back to model-level fit statistics. *)
(*
--# Model Summary
--#
--# Returns a tidy summary DataFrame for native models.
--#
--# @name summary
--# @param model :: Model The model object (e.g., from lm()).
--# @return :: Dict Tidy summary dictionary with `_tidy_df` and metadata.
--# @example
--#   s = summary(model)
--#   coefficients = s._tidy_df
--# @family stats
--# @seealso lm, fit_stats
--# @export
*)
let register env =
  Env.add "summary"
    (make_builtin ~name:"summary" 1 (fun args _env ->
      match args with
      | [VDict pairs] ->
        let tidy_df = List.assoc_opt "_tidy_df" pairs in
        let model_class = List.assoc_opt "class" pairs in
        let model_type = List.assoc_opt "model_type" pairs in
        let mining_function = List.assoc_opt "mining_function" pairs in
        let family = List.assoc_opt "family" pairs in
        let link = List.assoc_opt "link" pairs in
        let summary_dict tidy_df_value extra_pairs =
          VDict (
            ("_tidy_df", tidy_df_value) ::
            (match model_class with Some v -> [("model_class", v)] | None -> []) @
            (match model_type with Some v -> [("model_type", v)] | None -> []) @
            (match mining_function with Some v -> [("mining_function", v)] | None -> []) @
            extra_pairs @
            [("class", VString "summary")]
          )
        in

        (match tidy_df with
          | Some ((VDataFrame _) as tidy_df_value) ->
              summary_dict tidy_df_value
                ((match family with Some v -> [("family", v)] | None -> []) @
                 (match link with Some v -> [("link", v)] | None -> []))
          | _ ->
            (match Fit_stats.summary_metrics_for_model pairs with
             | Some stats_df ->
                  summary_dict stats_df [("summary_type", VString "fit_stats")]
             | None ->
                Error.type_error "Function `summary` expects a native model object.")
      | [VError _ as e] -> e
      | _ ->
        Error.type_error "Function `summary` expects a native model object."
    ))
    env
