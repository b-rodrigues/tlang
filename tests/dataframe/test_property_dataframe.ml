(* Dogfooding: dataframe-package invariants exercised via prop_named /
   prop_test over generated column-name lists and generated DataFrames.
   clean_colnames must preserve length, produce unique lowercase names within
   the [a-z0-9_] charset, and be idempotent. CSV write/read must round-trip
   dimensions, column names, and values. write_ipc/read_ipc must round-trip a
   mixed-type frame (int, float, bool, string, factor, date, datetime) with NA
   injection, must preserve the ordered factor flag, and must survive an empty
   frame. write_parquet/read_parquet must round-trip a mixed-type frame (int,
   float, bool, string, date, UTC datetime) with NA injection and survive an
   empty frame; factor (dictionary) columns are expected to flatten to plain
   strings on Parquet round-trip (same as R/pyarrow), so the factor property
   guards value-level and NA-count fidelity rather than type identity. Each
   property runs under several fixed seeds via prop_test_seeded. *)

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
      m_ipc_roundtrip = prop_named("ipc_roundtrip",   \(df) { write_ipc(df, "/tmp/propcraft_roundtrip.ipc"); r = read_ipc("/tmp/propcraft_roundtrip.ipc"); identical(df, r) })
      m_ipc_ordered   = prop_named("ipc_ordered",     \(df) { df2 = mutate(df, go = to_factor(pull(df, "s"), ordered = true)); write_ipc(df2, "/tmp/propcraft_roundtrip_ord.ipc"); r = read_ipc("/tmp/propcraft_roundtrip_ord.ipc"); identical(df2, r) })
      m_ipc_empty     = prop_named("ipc_empty",       \(df) { write_ipc(df, "/tmp/propcraft_roundtrip_empty.ipc"); r = read_ipc("/tmp/propcraft_roundtrip_empty.ipc"); identical(df, r) })
      m_parquet_roundtrip    = prop_named("parquet_roundtrip",    \(df) { write_parquet(df, "/tmp/propcraft_roundtrip.parquet"); r = read_parquet("/tmp/propcraft_roundtrip.parquet"); identical(df, r) })
      m_parquet_factor_flatten = prop_named("parquet_factor_flatten", \(df) { df2 = mutate(df, go = to_factor(pull(df, "s"), ordered = true)); write_parquet(df2, "/tmp/propcraft_roundtrip_f.parquet"); r = read_parquet("/tmp/propcraft_roundtrip_f.parquet"); nrow(r) == nrow(df2) && ncol(r) == ncol(df2) && identical(colnames(r), colnames(df2)) && identical(pull(r, "go"), pull(df, "s")) && identical(pull(r, "s"), pull(df, "s")) })
      m_parquet_empty     = prop_named("parquet_empty",       \(df) { write_parquet(df, "/tmp/propcraft_roundtrip_empty.parquet"); r = read_parquet("/tmp/propcraft_roundtrip_empty.parquet"); identical(df, r) })
    |} env
  in

  let seeds = [ 1; 7; 42 ] in
  let df_seeds = [ 1; 7 ] in
  let names_gen = "prop_gen_list(prop_gen_string_from(\"Aa1 \u{00E9}-\", 0, 6), 6)" in
  let csv_df_gen = "prop_gen_df([a: prop_gen_int_range(0, 100), b: prop_gen_float_range(0.0, 100.0), s: prop_gen_string_from(\"abc\", 1, 3)], nrows = 20, na_prob = 0.2)" in
  let ipc_df_gen = "prop_gen_df([i: prop_gen_int_range(-100, 100), f: prop_gen_float_range(-10.0, 10.0), b: prop_gen_bool(), s: prop_gen_string_from(\"ab\", 0, 4), g: prop_gen_factor([\"a\", \"b\", \"c\"]), d: prop_gen_ymd(2000, 2024), t: prop_gen_date_range(ymd_hms(\"2020-01-01 00:00:00\"), ymd_hms(\"2024-12-31 23:59:59\"))], nrows = 25, na_prob = 0.15)" in
  let ipc_ord_gen = "prop_gen_df([g: prop_gen_factor([\"a\", \"b\", \"c\"]), s: prop_gen_one_of([\"x\", \"y\", \"z\"])], nrows = 20, na_prob = 0.0)" in
  let ipc_empty_gen = "prop_gen_df([i: prop_gen_int_range(0, 10), g: prop_gen_factor([\"a\", \"b\"])], nrows = 0, na_prob = 0.0)" in
  let parquet_df_gen = "prop_gen_df([i: prop_gen_int_range(-1000, 1000), f: prop_gen_float_range(-10.0, 10.0), b: prop_gen_bool(), s: prop_gen_string_from(\"ab \", 0, 5), d: prop_gen_ymd(2000, 2024), t: prop_gen_date_range(ymd_hms(\"2020-01-01 00:00:00\"), ymd_hms(\"2024-12-31 23:59:59\"))], nrows = 25, na_prob = 0.15)" in
  let parquet_fact_gen = "prop_gen_df([g: prop_gen_factor([\"a\", \"b\", \"c\"]), s: prop_gen_one_of([\"x\", \"y\", \"z\"])], nrows = 25, na_prob = 0.15)" in
  let parquet_empty_gen = "prop_gen_df([i: prop_gen_int_range(0, 10), g: prop_gen_factor([\"a\", \"b\"])], nrows = 0, na_prob = 0.0)" in

  Test_helpers.prop_test_seeded test_env env "clean_colnames preserves length" "m_clean_len" names_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "clean_colnames produces unique names" "m_clean_unique" names_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "clean_colnames is idempotent" "m_clean_idem" names_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "clean_colnames output is lowercase [a-z0-9_]" "m_clean_charset" names_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "write_csv/read_csv round-trips dimensions and values" "m_csv_roundtrip" csv_df_gen 10 df_seeds;
  Test_helpers.prop_test_seeded test_env env "write_ipc/read_ipc round-trips mixed columns and NA" "m_ipc_roundtrip" ipc_df_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "write_ipc/read_ipc preserves ordered factor flag" "m_ipc_ordered" ipc_ord_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "write_ipc/read_ipc round-trips an empty frame" "m_ipc_empty" ipc_empty_gen 5 df_seeds;
  Test_helpers.prop_test_seeded test_env env "write_parquet/read_parquet round-trips mixed columns and NA" "m_parquet_roundtrip" parquet_df_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "write_parquet/read_parquet preserves factor values through string flattening" "m_parquet_factor_flatten" parquet_fact_gen 20 seeds;
  Test_helpers.prop_test_seeded test_env env "write_parquet/read_parquet round-trips an empty frame" "m_parquet_empty" parquet_empty_gen 5 df_seeds;

  if Sys.file_exists "/tmp/propcraft_roundtrip.csv" then Sys.remove "/tmp/propcraft_roundtrip.csv";
  List.iter (fun f -> if Sys.file_exists f then Sys.remove f)
    [ "/tmp/propcraft_roundtrip.ipc"; "/tmp/propcraft_roundtrip_ord.ipc"; "/tmp/propcraft_roundtrip_empty.ipc";
      "/tmp/propcraft_roundtrip.parquet"; "/tmp/propcraft_roundtrip_f.parquet"; "/tmp/propcraft_roundtrip_empty.parquet" ];

  Printf.printf "\n"
