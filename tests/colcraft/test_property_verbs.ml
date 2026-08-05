(* Dogfooding: exercise colcraft and stats verbs with prop_named / prop_test
   over multiple generated DataFrame generators. Named properties codify a property
   once; prop_test runs it against several generator specs. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — colcraft/stats verbs:\n";
  let env = Packages.init_env () in

  (* `right` lookup table must be defined before macros that reference it *)
  let (_, env) =
    eval_string_env "right = to_dataframe([[g: \"a\", val: 1], [g: \"b\", val: 2]])" env
  in

  let (_, env) =
    eval_string_env {|
      m_mutate   = prop_named("mutate_preserves_nrow",   \(df) nrow(mutate(df, $z = $x * 2)) == nrow(df))
      m_arrange  = prop_named("arrange_preserves_nrow",   \(df) nrow(arrange(df, $x)) == nrow(df))
      m_filter   = prop_named("filter_leq_input",         \(df) nrow(filter(df, $x > 50)) <= nrow(df))
      m_gsum     = prop_named("group_summarize_equals_n", \(df) to_integer(sum((df |> group_by($g) |> summarize($cnt = n())).cnt)) == nrow(df))
      m_distinct = prop_named("distinct_gte_input",       \(df) nrow(distinct(df)) <= nrow(df))
      m_head     = prop_named("head_slices_to_5",         \(df) nrow(head(df, 5)) == 5)
      m_slice    = prop_named("slice_sample_keeps_5",     \(df) nrow(slice_sample(df, n = 5)) == 5)
      m_mean     = prop_named("mean_in_range",            \(df) is_na(mean(df |> pull("x"), na_rm = true)) || (mean(df |> pull("x"), na_rm = true) >= 0.0 && mean(df |> pull("x"), na_rm = true) <= 100.0))
      m_sd       = prop_named("sd_nonnegative",           \(df) is_na(sd(df |> pull("x"), na_rm = true)) || sd(df |> pull("x"), na_rm = true) >= 0.0)
      m_join     = prop_named("left_join_preserves_nrow", \(df) nrow(left_join(df, right, by = $g)) == nrow(df))
      m_fill     = prop_named("fill_preserves_nrow",      \(df) nrow(fill(df, $x)) == nrow(df))
      m_df_from  = prop_named("df_from_mutate_preserves", \(df) nrow(mutate(df, $z = $x * 2)) == nrow(df))
      m_drop_na  = prop_named("drop_na_subsets_rows",     \(df) nrow(drop_na(df)) <= nrow(df))
      m_drop_na_d = prop_named("drop_na_col_subsets_rows", \(df) nrow(drop_na(df, $d)) <= nrow(df))
      m_arrange_id = prop_named("arrange_idempotent",     \(df) identical(arrange(df, $x) |> pull("x"), arrange(arrange(df, $x), $x) |> pull("x")))
      m_rename_col = prop_named("rename_preserves_ncol",  \(df) ncol(rename(df, $z = $x)) == ncol(df))
      m_mutate_sel = prop_named("mutate_then_select",     \(df) ncol(mutate(select(df, $x), $z = $x * 2)) == 2)
      m_distinct_nd = prop_named("distinct_leq_nrow",     \(df) nrow(distinct(df)) <= nrow(df))
      m_drop_na_nan = prop_named("drop_na_on_float",      \(df) nrow(drop_na(df, $f)) <= nrow(df))
    |} env
  in

  (* Two generator specs per property to dogfood macro reuse *)
  let float_df  = "prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 40, na_prob = 0.2)" in
  let int_df    = "prop_gen_df([x: prop_gen_int_range(0, 100)], nrows = 40, na_prob = 0.2)" in
  let factor_df = "prop_gen_df([g: prop_gen_factor([\"a\", \"b\"])], nrows = 40, na_prob = 0.0)" in
  let str_df    = "prop_gen_df([g: prop_gen_one_of([\"a\", \"b\"])], nrows = 40, na_prob = 0.0)" in
  let fct_int_df = "prop_gen_df([g: prop_gen_factor([\"a\", \"b\"]), x: prop_gen_int_range(1, 5)], nrows = 40, na_prob = 0.2)" in
  let str_flt_df = "prop_gen_df([g: prop_gen_one_of([\"a\", \"b\"]), x: prop_gen_float_range(0.0, 100.0)], nrows = 40, na_prob = 0.2)" in
  let fct_na_df  = "prop_gen_df([g: prop_gen_factor([\"a\", \"b\"])], nrows = 30, na_prob = 0.2)" in
  let str_na_df  = "prop_gen_df([g: prop_gen_one_of([\"a\", \"b\"])], nrows = 30, na_prob = 0.2)" in
  let df_from_gen = "prop_gen_df_from(mt, nrows = 40, na_prob = 0.2)" in
  let (_, env) = eval_string_env "mt = to_dataframe([x: [1, 2, 3], s: [\"a\", \"b\", \"c\"], f: to_factor([\"p\", \"q\", \"p\"])])" env in
  let (_, env) = eval_string_env "mt2 = to_dataframe([x: [10, 20, 30], y: [1.5, 3.0, 5.5]])" env in
  let date_df    = "prop_gen_df([d: prop_gen_ymd(2000, 2024), x: prop_gen_int_range(0, 100)], nrows = 30, na_prob = 0.3)" in
  let nan_df     = "prop_gen_df([f: prop_gen_one_of([to_float(\"NaN\"), 1.0, 2.0])], nrows = 20, na_prob = 0.0)" in

  (* Row-preserving verbs *)
  test_env env "mutate preserves nrow (float)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_mutate, %s, n = 25)" float_df) "PASS";
  test_env env "mutate preserves nrow (int)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_mutate, %s, n = 25)" int_df) "PASS";
  test_env env "arrange preserves nrow (float)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_arrange, %s, n = 25)" float_df) "PASS";
  test_env env "arrange preserves nrow (int)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_arrange, %s, n = 25)" int_df) "PASS";
  test_env env "filter output <= input (float)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_filter, %s, n = 25)" float_df) "PASS";
  test_env env "filter output <= input (int)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_filter, %s, n = 25)" int_df) "PASS";

  (* Row-count algebra — 2 gens each *)
  test_env env "group_by+summarize group sizes sum to nrow (factor)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_gsum, %s, n = 25)" factor_df) "PASS";
  test_env env "group_by+summarize group sizes sum to nrow (str)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_gsum, %s, n = 25)" str_df) "PASS";
  test_env env "distinct never grows rows (int_range)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_distinct, %s, n = 25)" int_df) "PASS";
  test_env env "distinct never grows rows (str)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_distinct, %s, n = 25)" str_df) "PASS";
  test_env env "head slices to fixed size (int_range)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_head, %s, n = 25)" int_df) "PASS";
  test_env env "head slices to fixed size (str)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_head, %s, n = 25)" str_df) "PASS";
  test_env env "slice_sample keeps requested size (int_range)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_slice, %s, n = 25)" int_df) "PASS";
  test_env env "slice_sample keeps requested size (str)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_slice, %s, n = 25)" str_df) "PASS";

  (* stats verbs with na_rm *)
  test_env env "mean with na_rm stays in range (float)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_mean, %s, n = 25)" float_df) "PASS";
  test_env env "mean with na_rm stays in range (int)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_mean, %s, n = 25)" int_df) "PASS";
  test_env env "sd with na_rm non-negative (float)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_sd, %s, n = 25)" float_df) "PASS";
  test_env env "sd with na_rm non-negative (int)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_sd, %s, n = 25)" int_df) "PASS";

  (* joins against fixed lookup *)
  test_env env "left_join preserves rows (factor)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_join, %s, n = 25)" factor_df) "PASS";
  test_env env "left_join preserves rows (str)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_join, %s, n = 25)" str_df) "PASS";
  test_env env "left_join preserves rows under NA keys (factor)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_join, %s, n = 25)" fct_na_df) "PASS";
  test_env env "left_join preserves rows under NA keys (str)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_join, %s, n = 25)" str_na_df) "PASS";

  (* fill *)
  test_env env "fill preserves nrow (factor+int)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_fill, %s, n = 25)" fct_int_df) "PASS";
  test_env env "fill preserves nrow (str+float)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_fill, %s, n = 25)" str_flt_df) "PASS";

  (* bug-fix regressions: drop_na on date columns, NaN dedup, arrange idempotence *)
  test_env env "drop_na never grows rows (date+int df)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_drop_na, %s, n = 25)" date_df) "PASS";
  test_env env "drop_na on a date column never grows rows"
    (Printf.sprintf "set_seed(1)\nprop_test(m_drop_na_d, %s, n = 25)" date_df) "PASS";
  test_env env "arrange is idempotent (int df)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_arrange_id, %s, n = 25)" int_df) "PASS";
  test_env env "arrange is idempotent (date df)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_arrange_id, %s, n = 25)" date_df) "PASS";
  test_env env "rename preserves column count"
    (Printf.sprintf "set_seed(1)\nprop_test(m_rename_col, %s, n = 25)" float_df) "PASS";
  test_env env "mutate then select yields expected columns"
    (Printf.sprintf "set_seed(1)\nprop_test(m_mutate_sel, %s, n = 25)" float_df) "PASS";
  test_env env "distinct never grows rows (float df)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_distinct_nd, %s, n = 25)" float_df) "PASS";
  test_env env "drop_na on NaN-injecting float column never grows rows"
    (Printf.sprintf "set_seed(1)\nprop_test(m_drop_na_nan, %s, n = 25)" nan_df) "PASS";

  (* schema-derived generator *)
  test_env env "prop_gen_df_from round-trips mutate via macro"
    (Printf.sprintf "set_seed(1)\nprop_test(m_df_from, %s, n = 25)" df_from_gen) "PASS";
  (* same macro, second generator: coarsen the df *)
  let (_, env) = eval_string_env "mt2 = to_dataframe([x: [1, 1, 2, 2, 3]], s: [\"z\", \"z\", \"z\"])" env in
  test_env env "prop_gen_df_from round-trips mutate via macro (smaller schema)"
    "set_seed(1)\nprop_test(m_df_from, prop_gen_df_from(mt2, nrows = 40, na_prob = 0.2), n = 25)"
    "PASS";

  Printf.printf "\n"
