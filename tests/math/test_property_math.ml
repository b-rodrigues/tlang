(* Dogfooding: algebraic invariants of math functions exercised via
   prop_named / prop_test over generated scalar domains. Each property runs
   under several fixed seeds via prop_test_seeded so that seed-dependent
   counterexamples cannot hide behind a single canonical seed. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — math:\n";
  let env = Packages.init_env () in

  let (_, env) =
    eval_string_env {|
      m_sqrt_abs      = prop_named("sqrt_abs",        \(x) sqrt(x * x) == abs(x))
      m_abs_geq        = prop_named("abs_geq_x",       \(x) abs(x) >= x)
      m_log_exp        = prop_named("log_exp_roundtrip", \(x) abs(log(exp(x)) - x) < 0.0001)
      m_exp_log        = prop_named("exp_log_roundtrip", \(x) x <= 0.0 || abs(exp(log(x)) - x) < 0.0001)
      m_sin_cos        = prop_named("sin_cos_identity", \(x) abs((sin(x) * sin(x) + cos(x) * cos(x)) - 1.0) < 0.0001)
      m_tanh_range     = prop_named("tanh_in_1_1",     \(x) tanh(x) >= -1.0 && tanh(x) <= 1.0)
      m_floor_ceil     = prop_named("floor_ceil",      \(x) floor(x) <= x && x <= ceiling(x))
      m_sign_abs       = prop_named("sign_abs",        \(x) sign(x) * abs(x) == x)
      m_round_dev       = prop_named("round_dev",      \(x) abs(round(x) - x) <= 0.5)
      m_abs_nonneg      = prop_named("abs_nonneg",     \(x) abs(x) >= 0.0)
      m_sqrt_nonneg     = prop_named("sqrt_nonneg",    \(x) x < 0.0 || sqrt(x) >= 0.0)
      m_pow_square      = prop_named("pow_square",     \(n) pow(n, 2) == n * n)
      m_int_min_le_max  = prop_named("int_min_le_max", \(xs) min(xs) <= max(xs))
      m_floor_round_ceil = prop_named("floor_round_ceil", \(x) floor(x) <= round(x) && round(x) <= ceiling(x))
      m_abs_idem       = prop_named("abs_idem",        \(x) abs(abs(x)) == abs(x))
      m_floor_neg      = prop_named("floor_neg_ceil",  \(x) floor(x) == -ceiling(-x))
      m_sign_class     = prop_named("sign_class",      \(x) ifelse(x > 0.0, 1.0, ifelse(x < 0.0, -1.0, 0.0)) == sign(x))
      m_exp_pos        = prop_named("exp_pos",         \(x) exp(x) > 0.0)
      m_cos_range      = prop_named("cos_in_1_1",      \(x) cos(x) >= -1.0 && cos(x) <= 1.0)
      m_round_half     = prop_named("round_half_away", \(x) round(x) == ifelse(x >= 0.0, floor(x + 0.5), ceiling(x - 0.5)))
      m_pow_zero       = prop_named("pow_zero",        \(n) pow(n, 0) == 1)
      m_mod_smaller    = prop_named("mod_smaller",     \(xy) get(xy, 1) == 0 || abs(get(xy, 0) % get(xy, 1)) < abs(get(xy, 1)))
      m_div_mod_id     = prop_named("div_mod_id",      \(xy) get(xy, 1) == 0 || to_integer(get(xy, 0) / get(xy, 1)) * get(xy, 1) + (get(xy, 0) % get(xy, 1)) == get(xy, 0))
    |} env
  in

  let seeds = [ 1; 7; 42 ] in
  let float_domain   = "prop_gen_float_range(-100.0, 100.0)" in
  let pos_float      = "prop_gen_float_range(0.0, 100.0)" in
  let small_float    = "prop_gen_float_range(-10.0, 10.0)" in
  let int_domain     = "prop_gen_int_range(-50, 50)" in
  let int_pair       = "prop_gen_list(prop_gen_int_range(-50, 50), 2)" in

  Test_helpers.prop_test_seeded test_env env "sqrt(x*x) == abs(x) on positive floats" "m_sqrt_abs" pos_float 30 seeds;
  Test_helpers.prop_test_seeded test_env env "abs(x) >= x on float domain" "m_abs_geq" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "log(exp(x)) ~ x on small floats" "m_log_exp" small_float 30 seeds;
  Test_helpers.prop_test_seeded test_env env "exp(log(x)) ~ x on positive floats" "m_exp_log" pos_float 30 seeds;
  Test_helpers.prop_test_seeded test_env env "sin^2 + cos^2 ~ 1 on float domain" "m_sin_cos" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "tanh(x) in [-1, 1]" "m_tanh_range" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "floor <= x <= ceiling" "m_floor_ceil" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "sign(x) * abs(x) == x" "m_sign_abs" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "round(x) within 0.5 of x" "m_round_dev" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "abs(x) >= 0" "m_abs_nonneg" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "sqrt(x) >= 0 for x >= 0" "m_sqrt_nonneg" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "pow(n, 2) == n * n on integers" "m_pow_square" int_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "min(xs) <= max(xs) on integer pairs" "m_int_min_le_max" int_pair 30 seeds;
  Test_helpers.prop_test_seeded test_env env "floor(x) <= round(x) <= ceiling(x)" "m_floor_round_ceil" float_domain 30 seeds;

  (* Hardened invariants *)
  Test_helpers.prop_test_seeded test_env env "abs is idempotent" "m_abs_idem" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "floor(x) == -ceiling(-x)" "m_floor_neg" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "sign classifies into -1/0/+1" "m_sign_class" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "exp(x) > 0" "m_exp_pos" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "cos(x) in [-1, 1]" "m_cos_range" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "round rounds half away from zero" "m_round_half" float_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "pow(n, 0) == 1 on integers" "m_pow_zero" int_domain 30 seeds;
  Test_helpers.prop_test_seeded test_env env "|a mod b| < |b| for b != 0" "m_mod_smaller" int_pair 30 seeds;
  Test_helpers.prop_test_seeded test_env env "trunc(a/b)*b + a mod b == a for b != 0" "m_div_mod_id" int_pair 30 seeds;

  Printf.printf "\n"
