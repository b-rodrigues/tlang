(* Dogfooding: algebraic invariants of math functions exercised via
   prop_named / prop_test over generated scalar domains. *)

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
    |} env
  in

  let float_domain   = "prop_gen_float_range(-100.0, 100.0)" in
  let pos_float      = "prop_gen_float_range(0.0, 100.0)" in
  let small_float    = "prop_gen_float_range(-10.0, 10.0)" in

  test_env env "sqrt(x*x) == abs(x) on positive floats"
    (Printf.sprintf "set_seed(1)\nprop_test(m_sqrt_abs, %s, n = 30)" pos_float) "PASS";

  test_env env "abs(x) >= x on float domain"
    (Printf.sprintf "set_seed(1)\nprop_test(m_abs_geq, %s, n = 30)" float_domain) "PASS";

  test_env env "log(exp(x)) ~ x on small floats"
    (Printf.sprintf "set_seed(1)\nprop_test(m_log_exp, %s, n = 30)" small_float) "PASS";

  test_env env "exp(log(x)) ~ x on positive floats"
    (Printf.sprintf "set_seed(1)\nprop_test(m_exp_log, %s, n = 30)" pos_float) "PASS";

  test_env env "sin^2 + cos^2 ~ 1 on float domain"
    (Printf.sprintf "set_seed(1)\nprop_test(m_sin_cos, %s, n = 30)" float_domain) "PASS";

  test_env env "tanh(x) in [-1, 1]"
    (Printf.sprintf "set_seed(1)\nprop_test(m_tanh_range, %s, n = 30)" float_domain) "PASS";

  test_env env "floor <= x <= ceiling"
    (Printf.sprintf "set_seed(1)\nprop_test(m_floor_ceil, %s, n = 30)" float_domain) "PASS";

  test_env env "sign(x) * abs(x) == x"
    (Printf.sprintf "set_seed(1)\nprop_test(m_sign_abs, %s, n = 30)" float_domain) "PASS";

  test_env env "round(x) within 0.5 of x"
    (Printf.sprintf "set_seed(1)\nprop_test(m_round_dev, %s, n = 30)" float_domain) "PASS";

  test_env env "abs(x) >= 0"
    (Printf.sprintf "set_seed(1)\nprop_test(m_abs_nonneg, %s, n = 30)" float_domain) "PASS";

  test_env env "sqrt(x) >= 0 for x >= 0"
    (Printf.sprintf "set_seed(1)\nprop_test(m_sqrt_nonneg, %s, n = 30)" float_domain) "PASS";

  Printf.printf "\n"
