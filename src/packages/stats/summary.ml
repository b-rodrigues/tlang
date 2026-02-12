open Ast

(** summary(model) — returns the tidy coefficients DataFrame from an lm() model.
    Equivalent to broom::tidy(). *)
let register env =
  Env.add "summary"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VDict pairs] ->
        (match List.assoc_opt "_tidy_df" pairs with
         | Some (VDataFrame _ as df) -> df
         | _ ->
           make_error TypeError "summary() expects a model returned by lm()")
      | _ ->
        make_error TypeError "summary() expects a model returned by lm()"
    ))
    env
