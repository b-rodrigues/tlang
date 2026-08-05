(* Dogfooding: statistical invariants exercised via prop_named / prop_test
   over generated numeric vector domains. These properties are designed to be
   tight: they fail if aggregation/quantile/mode primitives silently mishandle
   typed values, tie-breaking, or degenerate inputs. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — stats:\n";
  let env = Packages.init_env () in

  let (_, env) =
    eval_string_env {|
      m_mode_member     = prop_named("mode_member",       \(v) sum(ifelse(v .== mode(v), 1, 0)) >= 1)
      m_mode_mixed      = prop_named("mode_mixed_member", \(v) sum(ifelse(v .== mode(v), 1, 0)) >= 1)
      m_mode_dom        = prop_named("mode_dominant",     \(x) mode([x, x, x, 0, 1]) == x)
      m_mode_na         = prop_named("mode_na_ignored",   \(x) mode([x, NA, x]) == x)
      m_var_sd          = prop_named("var_sd",            \(v) abs(sd(v) - sqrt(var(v))) < 0.0001)
      m_var_nonneg      = prop_named("var_nonneg",        \(v) var(v) >= 0.0)
      m_var_const       = prop_named("var_const_zero",    \(c) abs(var([c, c, c])) < 0.0001)
      m_mean_bounds     = prop_named("mean_in_range",     \(v) mean(v) >= min(v) && mean(v) <= max(v))
      m_mean_const      = prop_named("mean_const",        \(c) abs(mean([c, c, c, c]) - to_float(c)) < 0.0001)
      m_min_le_max      = prop_named("min_le_max",        \(v) min(v) <= max(v))
      m_range_minmax    = prop_named("range_minmax",      \(v) min(range(v)) == min(v) && max(range(v)) == max(v))
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

  let int_vec   = "prop_gen_vector(prop_gen_int_range(-20, 20), 10)" in
  let pos_vec   = "prop_gen_vector(prop_gen_int_range(1, 50), 10)" in
  let float_vec = "prop_gen_vector(prop_gen_float_range(-100.0, 100.0), 10)" in
  let int_dom   = "prop_gen_int_range(2, 9)" in
  let mixed_vec = "prop_gen_vector(prop_gen_one_of([0, 1, 2, true, false]), 12)" in
  let xy_df     = "prop_gen_df([x: prop_gen_float_range(-50.0, 50.0), y: prop_gen_float_range(-50.0, 50.0)], nrows = 20, na_prob = 0.0)" in

  (* mode *)
  test_env env "mode returns a member of the input (int vector)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_mode_member, %s, n = 30)" int_vec) "PASS";
  test_env env "mode returns a member of the input (mixed int/bool vector)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_mode_mixed, %s, n = 30)" mixed_vec) "PASS";
  test_env env "mode picks the dominant value over ties"
    (Printf.sprintf "set_seed(1)\nprop_test(m_mode_dom, %s, n = 30)" int_dom) "PASS";
  test_env env "mode skips NA values"
    (Printf.sprintf "set_seed(1)\nprop_test(m_mode_na, %s, n = 30)" int_dom) "PASS";

  (* variance / sd *)
  test_env env "sd == sqrt(var) on int vectors"
    (Printf.sprintf "set_seed(1)\nprop_test(m_var_sd, %s, n = 30)" int_vec) "PASS";
  test_env env "var >= 0 on float vectors"
    (Printf.sprintf "set_seed(1)\nprop_test(m_var_nonneg, %s, n = 30)" float_vec) "PASS";
  test_env env "var of a constant vector is zero"
    (Printf.sprintf "set_seed(1)\nprop_test(m_var_const, %s, n = 30)" int_dom) "PASS";

  (* mean *)
  test_env env "mean stays within [min, max]"
    (Printf.sprintf "set_seed(1)\nprop_test(m_mean_bounds, %s, n = 30)" int_vec) "PASS";
  test_env env "mean of a constant vector equals that constant"
    (Printf.sprintf "set_seed(1)\nprop_test(m_mean_const, %s, n = 30)" int_dom) "PASS";

  (* min/max/range *)
  test_env env "min <= max"
    (Printf.sprintf "set_seed(1)\nprop_test(m_min_le_max, %s, n = 30)" float_vec) "PASS";
  test_env env "range returns [min, max]"
    (Printf.sprintf "set_seed(1)\nprop_test(m_range_minmax, %s, n = 30)" int_vec) "PASS";

  (* quantiles *)
  test_env env "median quantile stays within [min, max]"
    (Printf.sprintf "set_seed(1)\nprop_test(m_quantile_bounds, %s, n = 30)" int_vec) "PASS";
  test_env env "quantile(0) == min and quantile(1) == max"
    (Printf.sprintf "set_seed(1)\nprop_test(m_quantile_edges, %s, n = 30)" int_vec) "PASS";
  test_env env "median == quantile(0.5)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_median_quantile, %s, n = 30)" int_vec) "PASS";

  (* correlation / covariance / spread *)
  test_env env "cor(v, v) == 1"
    (Printf.sprintf "set_seed(1)\nprop_test(m_cor_self, %s, n = 30)" float_vec) "PASS";
  test_env env "cov(x, y) == cov(y, x)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_cov_sym, %s, n = 20)" xy_df) "PASS";
  test_env env "cor stays within [-1, 1]"
    (Printf.sprintf "set_seed(1)\nprop_test(m_cor_range, %s, n = 20)" xy_df) "PASS";
  test_env env "iqr is non-negative"
    (Printf.sprintf "set_seed(1)\nprop_test(m_iqr_nonneg, %s, n = 30)" int_vec) "PASS";
  test_env env "fivenum endpoints match min and max"
    (Printf.sprintf "set_seed(1)\nprop_test(m_fivenum_bounds, %s, n = 30)" pos_vec) "PASS";

  Printf.printf "\n"
