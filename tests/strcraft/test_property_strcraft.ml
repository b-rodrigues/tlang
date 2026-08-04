(* Dogfooding: round-trip and idempotence invariants of string functions
   exercised via prop_named / prop_test over generated string domains. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — strcraft:\n";
  let env = Packages.init_env () in

  let (_, env) =
    eval_string_env {|
      m_split_join     = prop_named("split_join",     \(s) s == "" || str_join(str_split(s, ","), ",") == s)
      m_lower_idem    = prop_named("lower_idem",    \(s) to_lower(to_lower(s)) == to_lower(s))
      m_upper_idem    = prop_named("upper_idem",    \(s) to_upper(to_upper(s)) == to_upper(s))
      m_trim_nchar     = prop_named("trim_nchar",     \(s) str_nchar(str_trim(s)) <= str_nchar(s))
      m_starts_nchar   = prop_named("starts_nchar",   \(s) !starts_with(s, "ab") || str_nchar(s) >= 2)
      m_count_nonneg   = prop_named("count_nonneg",   \(s) str_count(s, "a") >= 0)
      m_substring_len  = prop_named("substring_len",  \(s) s == "" || str_nchar(str_substring(s, 0, 1)) == min([1, str_nchar(s)]))
      m_substring_self  = prop_named("substring_self",  \(s) s == "" || s == str_substring(s, 0, str_nchar(s)))
    |} env
  in

  let alpha_gen     = "prop_gen_string_from(\"abcdefgh\", 0, 12)" in
  let alphanum_gen  = "prop_gen_string_from(\"abc,def\", 0, 12)" in

  test_env env "str_split + str_join round-trip on comma-separated strings"
    (Printf.sprintf "set_seed(1)\nprop_test(m_split_join, %s, n = 30)" alphanum_gen) "PASS";

  test_env env "to_lower is idempotent"
    (Printf.sprintf "set_seed(1)\nprop_test(m_lower_idem, %s, n = 30)" alpha_gen) "PASS";

  test_env env "to_upper is idempotent"
    (Printf.sprintf "set_seed(1)\nprop_test(m_upper_idem, %s, n = 30)" alpha_gen) "PASS";

  test_env env "trim never increases length"
    (Printf.sprintf "set_seed(1)\nprop_test(m_trim_nchar, %s, n = 30)" alpha_gen) "PASS";

  test_env env "starts_with implies minimum length"
    (Printf.sprintf "set_seed(1)\nprop_test(m_starts_nchar, %s, n = 30)" alpha_gen) "PASS";

  test_env env "str_count is never negative"
    (Printf.sprintf "set_seed(1)\nprop_test(m_count_nonneg, %s, n = 30)" alpha_gen) "PASS";

  test_env env "str_substring(0, 1) length == min(1, str_nchar(s))"
    (Printf.sprintf "set_seed(1)\nprop_test(m_substring_len, %s, n = 30)" alpha_gen) "PASS";

  test_env env "str_substring(0, str_nchar(s)) == s"
    (Printf.sprintf "set_seed(1)\nprop_test(m_substring_self, %s, n = 30)" alpha_gen) "PASS";

  Printf.printf "\n"
