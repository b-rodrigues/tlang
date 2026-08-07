(* Dogfooding: dataframe-package invariants exercised via prop_named /
   prop_test over generated column-name lists and generated DataFrames.
   clean_colnames must preserve length, produce unique lowercase names within
   the [a-z0-9_] charset, and be idempotent. CSV write/read must round-trip
   dimensions, column names, and values. Each property runs under several
   fixed seeds via prop_test_seeded. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — dataframe:\n";
  let env = Packages.init_env () in

  let (_, env) =
    eval_string_env {|
      m_clean_len     = prop_named("clean_len",       \(names) length(clean_colnames(names)) == length(names))
      m_clean_unique  = prop_named("clean_unique",    \(names) n_distinct(clean_colnames(names)) == length(names))
      m_clean_idem    = prop_named("clean_idem",      \(names) identical(clean_colnames(names), clean_colnames(clean_colnames(names))))
      m_clean_charset = prop_named("clean_charset",   \(names) sum(ifelse(map(clean_colnames(names), \(n) str_detect(n, "^[a-z0-9_]+$")), 1, 0)) == length(names))
      m_csv_roundtrip = prop_named("csv_roundtrip",   \(df) { write_csv(df, "/tmp/propcraft_roundtrip.csv"); r = read_csv("/tmp/propcraft_roundtrip.csv"); nrow(r) == nrow(df) && ncol(r) == ncol(df) && identical(colnames(r), colnames(df)) && sum(pull(r, "a"), na_rm = true) == sum(pull(df, "a"), na_rm = true) })
    |} env
  in

  let seeds = [ 1; 7; 42 ] in
  let df_seeds = [ 1; 7 ] in
  let names_gen = "prop_gen_list(prop_gen_string_from(\"Aa1 \u{00E9}-\", 0, 6), 6)" in
  let csv_df_gen = "prop_gen_df([a: prop_gen_int_range(0, 100), b: prop_gen_float_range(0.0, 100.0), s: prop_gen_string_from(\"abc\", 1, 3)], nrows = 20, na_prob = 0.2)" in

  Test_helpers.prop_test_seeded test_env env "clean_colnames preserves length" "m_clean_len" names_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "clean_colnames produces unique names" "m_clean_unique" names_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "clean_colnames is idempotent" "m_clean_idem" names_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "clean_colnames output is lowercase [a-z0-9_]" "m_clean_charset" names_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "write_csv/read_csv round-trips dimensions and values" "m_csv_roundtrip" csv_df_gen 10 df_seeds;

  if Sys.file_exists "/tmp/propcraft_roundtrip.csv" then Sys.remove "/tmp/propcraft_roundtrip.csv";

  Printf.printf "\n"
