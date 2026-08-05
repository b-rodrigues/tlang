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
      m_split_rt       = prop_named("split_rt",       \(s) str_join(str_split(s, ""), "") == s)
      m_pad_width      = prop_named("pad_width",      \(s) str_nchar(str_pad(s, str_nchar(s) + 3, side = "left", pad = "x")) == str_nchar(s) + 3)
      m_trunc_width    = prop_named("trunc_width",    \(s) str_nchar(str_trunc(s, 3)) <= 3)
      m_repeat_length  = prop_named("repeat_length",  \(s) str_nchar(str_repeat(s, 5)) == 5 * str_nchar(s))
      m_case_rt        = prop_named("case_rt",        \(s) identical(to_lower(to_upper(s)), to_lower(s)))
      m_upper_case     = prop_named("upper_case",     \(s) str_nchar(s) == 0 || to_upper(s) != s)
      m_lower_case     = prop_named("lower_case",     \(s) str_nchar(s) == 0 || to_lower(s) != s)
      m_contains_idx   = prop_named("contains_idx",   \(s) contains(s, "a") == (index_of(s, "a") >= 0))
      m_detect_dot     = prop_named("detect_dot",     \(s) s == "" || str_detect(s, str_join(["^", str_repeat(".", str_nchar(s)), "$"], "")))
    |} env
  in

  let alpha_gen     = "prop_gen_string_from(\"abcdefgh\", 0, 12)" in
  let alphanum_gen  = "prop_gen_string_from(\"abc,def\", 0, 12)" in
  let multi_gen     = "prop_gen_string_from(\"h\u{00E9}\u{00E0}\u{00FC}xyz012\", 0, 12)" in
  let accented_gen  = "prop_gen_string_from(\"\u{00E9}\u{00E0}\u{00FC}\", 1, 10)" in
  let upper_acc_gen = "prop_gen_string_from(\"\u{00C9}\u{00C0}\u{00DC}\", 1, 10)" in

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

  (* Multibyte UTF-8 invariants — these are the ones that catch byte-based
     regressions in split/pad/trunc/repeat and case mapping. *)
  test_env env "str_split(s, \"\") + str_join round-trips multibyte strings"
    (Printf.sprintf "set_seed(1)\nprop_test(m_split_rt, %s, n = 30)" multi_gen) "PASS";

  test_env env "str_pad adds exactly the requested characters"
    (Printf.sprintf "set_seed(1)\nprop_test(m_pad_width, %s, n = 30)" multi_gen) "PASS";

  test_env env "str_trunc output is at most the requested width"
    (Printf.sprintf "set_seed(1)\nprop_test(m_trunc_width, %s, n = 30)" multi_gen) "PASS";

  test_env env "str_repeat length is n times the input length"
    (Printf.sprintf "set_seed(1)\nprop_test(m_repeat_length, %s, n = 30)" multi_gen) "PASS";

  test_env env "to_lower(to_upper(s)) == to_lower(s)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_case_rt, %s, n = 30)" multi_gen) "PASS";

  test_env env "to_upper changes accented input"
    (Printf.sprintf "set_seed(1)\nprop_test(m_upper_case, %s, n = 30)" accented_gen) "PASS";

  test_env env "to_lower changes accented input"
    (Printf.sprintf "set_seed(1)\nprop_test(m_lower_case, %s, n = 30)" upper_acc_gen) "PASS";

  test_env env "contains(s, \"a\") agrees with index_of(s, \"a\")"
    (Printf.sprintf "set_seed(1)\nprop_test(m_contains_idx, %s, n = 30)" multi_gen) "PASS";

  test_env env "str_detect(s, \"^.$\") holds for single non-empty strings"
    (Printf.sprintf "set_seed(1)\nprop_test(m_detect_dot, %s, n = 30)" multi_gen) "PASS";

  Printf.printf "\n"
