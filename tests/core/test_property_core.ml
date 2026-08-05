(* Dogfooding: functional invariants of core primitives exercised via
   prop_named / prop_test over generated domains. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — core:\n";
  let env = Packages.init_env () in

  let (_, env) =
    eval_string_env {|
      m_map_length    = prop_named("map_length",    \(xs) length(map(xs, \(x) x * 2)) == length(xs))
      m_identical     = prop_named("identical_self", \(x) identical(x, x) == true)
      m_ifelse_true   = prop_named("ifelse_true",   \(x) ifelse(true, x, -1) == x)
      m_ifelse_false  = prop_named("ifelse_false",  \(x) ifelse(false, -1, x) == x)
      m_roundtrip_int = prop_named("int_float_rt",  \(x) to_integer(to_float(x)) == x)
      m_map_identity  = prop_named("map_identity",  \(xs) identical(map(xs, \(x) x), xs))
      m_map_compose   = prop_named("map_compose",   \(xs) identical(map(map(xs, \(x) x + 1), \(x) x * 2), map(xs, \(x) (x + 1) * 2)))
      m_head_len      = prop_named("head_len",      \(xs) length(head(xs, 3)) == min([3, length(xs)]))
      m_tail_len      = prop_named("tail_len",      \(xs) length(tail(xs, 5)) == min([5, length(xs)]))
      m_sum_shift     = prop_named("sum_shift",     \(xs) sum(map(xs, \(x) x + 1)) == sum(xs) + length(xs))
    |} env
  in

  let int_gen    = "prop_gen_int_range(-100, 100)" in
  let bool_gen   = "prop_gen_bool()" in
  let list3_gen  = "prop_gen_list(prop_gen_int_range(-10, 10), 5)" in

  test_env env "map preserves list length"
    (Printf.sprintf "set_seed(1)\nprop_test(m_map_length, %s, n = 30)" list3_gen) "PASS";

  test_env env "identical(x, x) is always true (int)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_identical, %s, n = 30)" int_gen) "PASS";

  test_env env "identical(x, x) is always true (bool)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_identical, %s, n = 10)" bool_gen) "PASS";

  test_env env "ifelse(true, x, -1) == x"
    (Printf.sprintf "set_seed(1)\nprop_test(m_ifelse_true, %s, n = 30)" int_gen) "PASS";

  test_env env "ifelse(false, -1, x) == x"
    (Printf.sprintf "set_seed(1)\nprop_test(m_ifelse_false, %s, n = 30)" int_gen) "PASS";

  test_env env "to_integer(to_float(x)) == x round-trip"
    (Printf.sprintf "set_seed(1)\nprop_test(m_roundtrip_int, %s, n = 30)" int_gen) "PASS";

  test_env env "map with identity preserves the list"
    (Printf.sprintf "set_seed(1)\nprop_test(m_map_identity, %s, n = 30)" list3_gen) "PASS";

  test_env env "map composes f then g like a single lambda"
    (Printf.sprintf "set_seed(1)\nprop_test(m_map_compose, %s, n = 30)" list3_gen) "PASS";

  test_env env "head returns at most the requested prefix"
    (Printf.sprintf "set_seed(1)\nprop_test(m_head_len, %s, n = 30)" list3_gen) "PASS";

  test_env env "tail returns at most the requested suffix"
    (Printf.sprintf "set_seed(1)\nprop_test(m_tail_len, %s, n = 30)" list3_gen) "PASS";

  test_env env "sum of (x + 1) == sum(x) + length(x)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_sum_shift, %s, n = 30)" list3_gen) "PASS";

  Printf.printf "\n"
