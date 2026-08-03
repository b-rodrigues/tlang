(* Dogfooding: exercise colcraft and stats verbs with prop_macro / prop_test
   over multiple generated DataFrame generators. Macros codify a property
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
      m_mutate   = prop_macro("mutate_preserves_nrow",   \(df) nrow(mutate(df, $z = $x * 2)) == nrow(df))
      m_arrange  = prop_macro("arrange_preserves_nrow",   \(df) nrow(arrange(df, $x)) == nrow(df))
      m_filter   = prop_macro("filter_leq_input",         \(df) nrow(filter(df, $x > 50)) <= nrow(df))
      m_gsum     = prop_macro("group_summarize_equals_n", \(df) to_integer(sum((df |> group_by($g) |> summarize($cnt = n())).cnt)) == nrow(df))
      m_distinct = prop_macro("distinct_gte_input",       \(df) nrow(distinct(df)) <= nrow(df))
      m_head     = prop_macro("head_slices_to_5",         \(df) nrow(head(df, 5)) == 5)
      m_slice    = prop_macro("slice_sample_keeps_5",     \(df) nrow(slice_sample(df, n = 5)) == 5)
      m_mean     = prop_macro("mean_in_range",            \(df) is_na(mean(df |> pull("x"), na_rm = true)) || (mean(df |> pull("x"), na_rm = true) >= 0.0 && mean(df |> pull("x"), na_rm = true) <= 100.0))
      m_sd       = prop_macro("sd_nonnegative",           \(df) is_na(sd(df |> pull("x"), na_rm = true)) || sd(df |> pull("x"), na_rm = true) >= 0.0)
      m_join     = prop_macro("left_join_preserves_nrow", \(df) nrow(left_join(df, right, by = $g)) == nrow(df))
      m_fill     = prop_macro("fill_preserves_nrow",      \(df) nrow(fill(df, $x)) == nrow(df))
      m_df_from  = prop_macro("df_from_mutate_preserves", \(df) nrow(mutate(df, $z = $x * 2)) == nrow(df))
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

  (* schema-derived generator *)
  test_env env "prop_gen_df_from round-trips mutate via macro"
    (Printf.sprintf "set_seed(1)\nprop_test(m_df_from, %s, n = 25)" df_from_gen) "PASS";
  (* same macro, second generator: coarsen the df *)
  let (_, env) = eval_string_env "mt2 = to_dataframe([x: [1, 1, 2, 2, 3]], s: [\"z\", \"z\", \"z\"])" env in
  test_env env "prop_gen_df_from round-trips mutate via macro (smaller schema)"
    "set_seed(1)\nprop_test(m_df_from, prop_gen_df_from(mt2, nrows = 40, na_prob = 0.2), n = 25)"
    "PASS";

  Printf.printf "\n"
