(* Dogfooding: round-trip and idempotence invariants of string functions
   exercised via prop_named / prop_test over generated string domains. Each
   property runs under several fixed seeds via prop_test_seeded. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — strcraft:\n";
  let env = Packages.init_env () in

  let (_, env) =
    eval_string_env {|
      m_split_join     = prop_named("split_join",     \(s) s == "" || str_join(str_split(s, ","), ",") == s)
      m_lower_idem    = prop_named("lower_idem",    \(s) to_lower(to_lower(s)) == to_lower(s))
      m_upper_idem    = prop_named("upper_idem",    \(s) to_upper(to_upper(s)) == to_upper(s))
      m_trim_nchar     = prop_named("trim_nchar",     \(s) str_nchar(str_trim(s)) <= str_nchar(s))
      m_trim_idem      = prop_named("trim_idem",      \(s) str_trim(str_trim(s)) == str_trim(s))
      m_trim_identity  = prop_named("trim_identity",  \(s) str_trim(s) == s || starts_with(s, " ") || ends_with(s, " "))
      m_starts_nchar   = prop_named("starts_nchar",   \(s) !starts_with(s, "ab") || str_nchar(s) >= 2)
      m_count_nonneg   = prop_named("count_nonneg",   \(s) str_count(s, "a") >= 0)
      m_substring_len  = prop_named("substring_len",  \(s) s == "" || str_nchar(str_substring(s, 0, 1)) == min([1, str_nchar(s)]))
      m_substring_self  = prop_named("substring_self",  \(s) s == "" || s == str_substring(s, 0, str_nchar(s)))
      m_split_rt       = prop_named("split_rt",       \(s) str_join(str_split(s, ""), "") == s)
      m_pad_width      = prop_named("pad_width",      \(s) str_nchar(str_pad(s, str_nchar(s) + 3, side = "left", pad = "x")) == str_nchar(s) + 3)
      m_trunc_width    = prop_named("trunc_width",    \(s) str_nchar(str_trunc(s, 3)) <= 3)
      m_repeat_length  = prop_named("repeat_length",  \(s) str_nchar(str_repeat(s, 5)) == 5 * str_nchar(s))
      m_repeat_join    = prop_named("repeat_join",    \(s) str_repeat(s, 2) == str_join([s, s], ""))
      m_case_rt        = prop_named("case_rt",        \(s) identical(to_lower(to_upper(s)), to_lower(s)))
      m_upper_case     = prop_named("upper_case",     \(s) str_nchar(s) == 0 || to_upper(s) != s)
      m_lower_case     = prop_named("lower_case",     \(s) str_nchar(s) == 0 || to_lower(s) != s)
      m_contains_idx   = prop_named("contains_idx",   \(s) contains(s, "a") == (index_of(s, "a") >= 0))
      m_detect_dot     = prop_named("detect_dot",     \(s) s == "" || str_detect(s, str_join(["^", str_repeat(".", str_nchar(s)), "$"], "")))
    |} env
  in

  let seeds = [ 1; 7; 42 ] in
  let alpha_gen     = "prop_gen_string_from(\"abcdefgh\", 0, 12)" in
  let alphanum_gen  = "prop_gen_string_from(\"abc,def\", 0, 12)" in
  let space_gen     = "prop_gen_string_from(\"ab c\", 0, 12)" in
  let multi_gen     = "prop_gen_string_from(\"h\u{00E9}\u{00E0}\u{00FC}xyz012\", 0, 12)" in
  let accented_gen  = "prop_gen_string_from(\"\u{00E9}\u{00E0}\u{00FC}\", 1, 10)" in
  let upper_acc_gen = "prop_gen_string_from(\"\u{00C9}\u{00C0}\u{00DC}\", 1, 10)" in

  Test_helpers.prop_test_seeded test_env env "str_split + str_join round-trip on comma-separated strings" "m_split_join" alphanum_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "to_lower is idempotent" "m_lower_idem" alpha_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "to_upper is idempotent" "m_upper_idem" alpha_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "trim never increases length" "m_trim_nchar" alpha_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "trim is idempotent" "m_trim_idem" space_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "trim is identity unless edge whitespace exists" "m_trim_identity" space_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "starts_with implies minimum length" "m_starts_nchar" alpha_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "str_count is never negative" "m_count_nonneg" alpha_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "str_substring(0, 1) length == min(1, str_nchar(s))" "m_substring_len" alpha_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "str_substring(0, str_nchar(s)) == s" "m_substring_self" alpha_gen 30 seeds;

  (* Multibyte UTF-8 invariants — these are the ones that catch byte-based
     regressions in split/pad/trunc/repeat and case mapping. *)
  Test_helpers.prop_test_seeded test_env env "str_split(s, \"\") + str_join round-trips multibyte strings" "m_split_rt" multi_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "str_pad adds exactly the requested characters" "m_pad_width" multi_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "str_trunc output is at most the requested width" "m_trunc_width" multi_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "str_repeat length is n times the input length" "m_repeat_length" multi_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "str_repeat(2) equals double concatenation" "m_repeat_join" multi_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "to_lower(to_upper(s)) == to_lower(s)" "m_case_rt" multi_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "to_upper changes accented input" "m_upper_case" accented_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "to_lower changes accented input" "m_lower_case" upper_acc_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "contains(s, \"a\") agrees with index_of(s, \"a\")" "m_contains_idx" multi_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "str_detect(s, \"^.$\") holds for single non-empty strings" "m_detect_dot" multi_gen 30 seeds;

  Printf.printf "\n"
