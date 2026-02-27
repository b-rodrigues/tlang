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
        let tidy_df = List.assoc_opt "_tidy_df" pairs in
        let model_class = List.assoc_opt "class" pairs in
        let family = List.assoc_opt "family" pairs in
        let link = List.assoc_opt "link" pairs in
        
        (match tidy_df with
         | Some (VDataFrame _) ->
             VDict (
               ("_tidy_df", Option.get tidy_df) ::
               (match model_class with Some v -> [("model_class", v)] | None -> []) @
               (match family with Some v -> [("family", v)] | None -> []) @
               (match link with Some v -> [("link", v)] | None -> []) @
               [("class", VString "summary")]
             )
         | _ ->
           Error.type_error "Function `summary` expects a model returned by `lm` or `glm`.")
      | _ ->
        Error.type_error "Function `summary` expects a model returned by `lm` or `glm`."
    ))
    env
