(* Dogfooding: statistical invariants exercised via prop_named / prop_test
   over generated numeric vector domains. These properties are designed to be
   tight: they fail if aggregation/quantile/mode primitives silently mishandle
   typed values, tie-breaking, or degenerate inputs. Each property runs under
   several fixed seeds via prop_test_seeded. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — stats:\n";
  let env = Packages.init_env () in

  let (_, env) =
    eval_string_env {|
      m_mode_member     = prop_named("mode_member",       \(v) sum(ifelse(v .== mode(v), 1, 0)) >= 1)
      m_mode_mixed      = prop_named("mode_mixed_member", \(v) sum(ifelse(v .== mode(v), 1, 0)) >= 1)
      m_mode_dom        = prop_named("mode_dominant",     \(x) mode([x, x, x, 0, 1]) == x)
      m_mode_na         = prop_named("mode_na_ignored",   \(x) mode([x, NA, x]) == x)
      m_mode_single     = prop_named("mode_single",       \(x) mode([x]) == x)
      m_var_sd          = prop_named("var_sd",            \(v) abs(sd(v) - sqrt(var(v))) < 0.0001)
      m_var_nonneg      = prop_named("var_nonneg",        \(v) var(v) >= 0.0)
      m_var_const       = prop_named("var_const_zero",    \(c) abs(var([c, c, c])) < 0.0001)
      m_var_shift       = prop_named("var_shift_invariant", \(c) abs(var([1.0, 2.0, 3.0, 4.0] .+ c) - var([1.0, 2.0, 3.0, 4.0])) < 0.0001)
      m_mean_bounds     = prop_named("mean_in_range",     \(v) mean(v) >= min(v) && mean(v) <= max(v))
      m_mean_const      = prop_named("mean_const",        \(c) abs(mean([c, c, c, c]) - to_float(c)) < 0.0001)
      m_mean_shift      = prop_named("mean_shift",        \(v) abs(mean(v .+ 3.0) - (mean(v) + 3.0)) < 0.0001)
      m_sd_scale        = prop_named("sd_scale",          \(v) abs(sd(v .* 2.0) - (2.0 * sd(v))) < 0.0001)
      m_min_le_max      = prop_named("min_le_max",        \(v) min(v) <= max(v))
      m_range_minmax    = prop_named("range_minmax",      \(v) min(range(v)) == min(v) && max(range(v)) == max(v))
      m_range_len       = prop_named("range_len",         \(v) length(range(v)) == 2)
      m_min_present     = prop_named("min_in_vector",     \(v) sum(ifelse(v .== min(v), 1, 0)) >= 1)
      m_max_present     = prop_named("max_in_vector",     \(v) sum(ifelse(v .== max(v), 1, 0)) >= 1)
      m_quantile_bounds = prop_named("quantile_bounds",   \(v) quantile(v, 0.5) >= min(v) && quantile(v, 0.5) <= max(v))
      m_quantile_edges  = prop_named("quantile_edges",    \(v) abs(quantile(v, 0.0) - min(v)) < 0.0001 && abs(quantile(v, 1.0) - max(v)) < 0.0001)
      m_median_quantile = prop_named("median_quantile",   \(v) abs(median(v) - quantile(v, 0.5)) < 0.0001)
      m_cor_self        = prop_named("cor_self",          \(v) abs(cor(v, v) - 1.0) < 0.0001)
      m_iqr_nonneg      = prop_named("iqr_nonneg",        \(v) iqr(v) >= 0.0)
      m_fivenum_bounds  = prop_named("fivenum_bounds",    \(v) min(fivenum(v)) >= min(v) - 0.0001 && max(fivenum(v)) <= max(v) + 0.0001)
      m_cov_sym         = prop_named("cov_sym",           \(df) abs(cov(df |> pull("x"), df |> pull("y")) - cov(df |> pull("y"), df |> pull("x"))) < 0.0001)
      m_cor_range       = prop_named("cor_range",         \(df) abs(cor(df |> pull("x"), df |> pull("y"))) <= 1.0)
    |} env
  in

  let seeds = [ 1; 7; 42 ] in
  let df_seeds = [ 1; 7 ] in
  let int_vec   = "prop_gen_vector(prop_gen_int_range(-20, 20), 10)" in
  let pos_vec   = "prop_gen_vector(prop_gen_int_range(1, 50), 10)" in
  let float_vec = "prop_gen_vector(prop_gen_float_range(-100.0, 100.0), 10)" in
  let int_dom   = "prop_gen_int_range(2, 9)" in
  let mixed_vec = "prop_gen_vector(prop_gen_one_of([0, 1, 2, true, false]), 12)" in
  let shift_c   = "prop_gen_float_range(-5.0, 5.0)" in
  let xy_df     = "prop_gen_df([x: prop_gen_float_range(-50.0, 50.0), y: prop_gen_float_range(-50.0, 50.0)], nrows = 20, na_prob = 0.0)" in

  (* mode *)
  Test_helpers.prop_test_seeded test_env env "mode returns a member of the input (int vector)" "m_mode_member" int_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "mode returns a member of the input (mixed int/bool vector)" "m_mode_mixed" mixed_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "mode picks the dominant value over ties" "m_mode_dom" int_dom 30 seeds;
  Test_helpers.prop_test_seeded test_env env "mode skips NA values" "m_mode_na" int_dom 30 seeds;
  Test_helpers.prop_test_seeded test_env env "mode of a single element is that element" "m_mode_single" int_dom 30 seeds;

  (* variance / sd *)
  Test_helpers.prop_test_seeded test_env env "sd == sqrt(var) on int vectors" "m_var_sd" int_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "var >= 0 on float vectors" "m_var_nonneg" float_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "var of a constant vector is zero" "m_var_const" int_dom 30 seeds;
  Test_helpers.prop_test_seeded test_env env "var is invariant under shifts" "m_var_shift" shift_c 30 seeds;

  (* mean *)
  Test_helpers.prop_test_seeded test_env env "mean stays within [min, max]" "m_mean_bounds" int_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "mean of a constant vector equals that constant" "m_mean_const" int_dom 30 seeds;
  Test_helpers.prop_test_seeded test_env env "mean shifts with the data" "m_mean_shift" float_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "sd scales linearly" "m_sd_scale" float_vec 30 seeds;

  (* min/max/range *)
  Test_helpers.prop_test_seeded test_env env "min <= max" "m_min_le_max" float_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "range returns [min, max]" "m_range_minmax" int_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "range has exactly two elements" "m_range_len" int_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "min is attained in the vector" "m_min_present" int_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "max is attained in the vector" "m_max_present" int_vec 30 seeds;

  (* quantiles *)
  Test_helpers.prop_test_seeded test_env env "median quantile stays within [min, max]" "m_quantile_bounds" int_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "quantile(0) == min and quantile(1) == max" "m_quantile_edges" int_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "median == quantile(0.5)" "m_median_quantile" int_vec 30 seeds;

  (* correlation / covariance / spread *)
  Test_helpers.prop_test_seeded test_env env "cor(v, v) == 1" "m_cor_self" float_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "cov(x, y) == cov(y, x)" "m_cov_sym" xy_df 20 df_seeds;
  Test_helpers.prop_test_seeded test_env env "cor stays within [-1, 1]" "m_cor_range" xy_df 20 df_seeds;
  Test_helpers.prop_test_seeded test_env env "iqr is non-negative" "m_iqr_nonneg" int_vec 30 seeds;
  Test_helpers.prop_test_seeded test_env env "fivenum endpoints match min and max" "m_fivenum_bounds" pos_vec 30 seeds;

  Printf.printf "\n"
