open Ast

(** summarize_model(model) — returns a tidy summarize_model DataFrame for native models.
    For regression models this is coefficient-level output; for tree/ensemble
    PMML models this falls back to model-level fit statistics. *)
(*
--# Model Summarize_model
--#
--# Returns a tidy summarize_model DataFrame for native models.
--#
--# @name summarize_model
--# @param model :: Model The model object (e.g., from lm()).
--# @return :: Dict Tidy summarize_model dictionary with `_tidy_df` and metadata.
--# @example
--#   s = summarize_model(model)
--#   coefficients = s._tidy_df
--# @family stats
--# @seealso lm, fit_stats
--# @export
*)
let register env =
  Env.add "summarize_model"
    (make_builtin ~name:"summarize_model" 1 (fun args _env ->
      match args with
      | [VDict pairs] ->
        let tidy_df = List.assoc_opt "_tidy_df" pairs in
        let model_class = List.assoc_opt "class" pairs in
        let model_type = List.assoc_opt "model_type" pairs in
        let mining_function = List.assoc_opt "mining_function" pairs in
        let family = List.assoc_opt "family" pairs in
        let link = List.assoc_opt "link" pairs in
        let summarize_model_dict tidy_df_value extra_pairs =
          VDict (
            ("_tidy_df", tidy_df_value) ::
            (match model_class with Some v -> [("model_class", v)] | None -> []) @
            (match model_type with Some v -> [("model_type", v)] | None -> []) @
            (match mining_function with Some v -> [("mining_function", v)] | None -> []) @
            extra_pairs @
            [("class", VString "summarize_model")]
          )
        in

        (match tidy_df with
          | Some ((VDataFrame _) as tidy_df_value) ->
              summarize_model_dict tidy_df_value
                ((match family with Some v -> [("family", v)] | None -> []) @
                 (match link with Some v -> [("link", v)] | None -> []))
          | _ ->
            (match Fit_stats.summarize_model_metrics_for_model pairs with
             | Some stats_df ->
                  summarize_model_dict stats_df [("summarize_model_type", VString "fit_stats")]
             | None ->
                Error.type_error "Function `summarize_model` expects a native model object."))
      | [VError _ as e] -> e
      | _ ->
        Error.type_error "Function `summarize_model` expects a native model object."
    ))
    env
