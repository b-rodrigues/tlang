(* src/packages/stats/anova.ml *)
open Ast

(** anova(model1, model2, ...) — performs analysis of variance (ANOVA) or likelihood ratio test. *)
(*
--# Analysis of Variance (ANOVA)
--#
--# Compares nested models using F-tests (for linear models) or Chi-square tests (for GLMs).
--#
--# @name anova
--# @param ... :: Model One or more model objects to compare.
--# @return :: DataFrame ANOVA table with statistics and p-values.
--# @example
--#   m1 = lm(mpg ~ wt, data = mtcars)
--#   m2 = lm(mpg ~ wt + hp, data = mtcars)
--#   anova(m1, m2)
--# @family stats
--# @export
*)
let register env =
  Env.add "anova"
    (make_builtin_named ~name:"anova" ~variadic:true 0 (fun args _env ->
      let models = List.filter_map (fun (_, v) ->
        match v with
        | VDict d -> Some d
        | _ -> None
      ) args in
      
      if List.length models < 2 then
        Error.value_error "Function `anova` requires at least two models to compare."
      else begin
        (* 1. Extract stats for all models *)
        let get_stats m =
          match List.assoc_opt "_model_data" m with
          | Some (VDict d) ->
              let get_f k = match List.assoc_opt k d with Some (VFloat f) -> f | _ -> 0.0 in
              let get_i k = match List.assoc_opt k d with Some (VInt i) -> i | _ -> 0 in
              let deviance = get_f "deviance" in
              let df_resid = get_i "df_residual" in
              let family = match List.assoc_opt "family" d with Some (VString s) -> s | _ -> "gaussian" in
              let name = match List.assoc_opt "name" m with Some (VString s) -> s | _ -> "(model)" in
              (name, deviance, df_resid, family)
          | _ -> ("", 0.0, 0, "gaussian")
        in
        
        let stats = List.map get_stats models in
        
        (* 2. Sort by df_residual descending (smaller model first) *)
        let sorted_stats = List.sort (fun (_, _, df1, _) (_, _, df2, _) -> compare df2 df1) stats in
        
        (* 3. Compute row-wise comparisons *)
        let results = ref [] in
        let prev_dev = ref 0.0 in
        let prev_df = ref 0 in
        
        List.iteri (fun i (name, dev, df, family) ->
          if i = 0 then begin
            results := (name, float_of_int df, dev, nan, nan, nan, nan) :: !results;
            prev_dev := dev;
            prev_df := df;
          end else begin
            let delta_df = !prev_df - df in
            let delta_dev = !prev_dev -. dev in
            
            let statistic, p_val = 
              if delta_df <= 0 then (nan, nan)
              else if family = "gaussian" then
                (* F-test *)
                let f_stat = (delta_dev /. float_of_int delta_df) /. (dev /. float_of_int df) in
                let p = 1.0 -. Distributions.pf f_stat delta_df df in
                (f_stat, p)
              else
                (* Chi-square test (LRT) *)
                let chi_stat = Float.abs delta_dev in
                let p = Distributions.pchisq chi_stat delta_df in
                (chi_stat, 1.0 -. p)
            in
            
            results := (name, float_of_int df, dev, float_of_int delta_df, delta_dev, statistic, p_val) :: !results;
            prev_dev := dev;
            prev_df := df;
          end
        ) sorted_stats;
        
        let results = List.rev !results in
        
        (* 4. Build DataFrame *)
        let mk_col f = Arrow_table.FloatColumn (Array.of_list (List.map (fun v -> if Float.is_nan v then None else Some v) f)) in
        let names = List.map (fun (n, _, _, _, _, _, _) -> Some n) results in
        let df_resid = List.map (fun (_, d, _, _, _, _, _) -> d) results in
        let deviance = List.map (fun (_, _, d, _, _, _, _) -> d) results in
        let delta_df = List.map (fun (_, _, _, d, _, _, _) -> d) results in
        let delta_dev = List.map (fun (_, _, _, _, d, _, _) -> d) results in
        let stat = List.map (fun (_, _, _, _, _, s, _) -> s) results in
        let pvals = List.map (fun (_, _, _, _, _, _, p) -> p) results in
        
        let columns = [
          ("model", Arrow_table.StringColumn (Array.of_list names));
          ("df_residual", mk_col df_resid);
          ("deviance", mk_col deviance);
          ("delta_df", mk_col delta_df);
          ("delta_deviance", mk_col delta_dev);
          ("statistic", mk_col stat);
          ("p_value", mk_col pvals);
        ] in
        
        let table = Arrow_table.create columns (List.length results) in
        VDataFrame { arrow_table = table; group_keys = [] }
      end
    )) env
