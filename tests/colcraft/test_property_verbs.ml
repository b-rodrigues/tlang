(* Dogfooding: exercise colcraft and stats verbs with prop_named / prop_test
   over multiple generated DataFrame generators. Named properties codify a property
   once; prop_test runs it against several generator specs. Each property runs
   under several fixed seeds via prop_test_seeded. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — colcraft/stats verbs:\n";
  let env = Packages.init_env () in

  (* `right` lookup table must be defined before macros that reference it *)
  let env = Test_helpers.eval_setup eval_string_env env "test_property_verbs:11" "right = to_dataframe([[g: \"a\", val: 1], [g: \"b\", val: 2]])" in

  let env = Test_helpers.eval_setup eval_string_env env "test_property_verbs:15" {|
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
      m_matches_ucp = prop_named("matches_unicode_class", \(df) (select(df, matches("^\\p{L}+$")) |> ncol) == ncol(df))
      m_contains_x  = prop_named("contains_filters",     \(df) (select(df, contains("x")) |> ncol) == ncol(df))
      m_sep_nrow    = prop_named("separate_rows_grows",  \(df) nrow(separate_rows(df, $x, sep = ";")) >= nrow(df))
      m_sep_ncol    = prop_named("separate_ncol",        \(df) (separate(df, $x, into = ["a", "b"], sep = ";") |> ncol) == ncol(df) + 1)
      m_select_nrow = prop_named("select_preserves_nrow", \(df) nrow(select(df, $x)) == nrow(df))
      m_distinct_idem = prop_named("distinct_idempotent", \(df) nrow(distinct(distinct(df))) == nrow(distinct(df)))
      m_pull_len    = prop_named("pull_len_nrow",        \(df) length(pull(df, "x")) == nrow(df))
      m_full_join_ge = prop_named("full_join_never_loses", \(df) nrow(full_join(df, right, by = $g)) >= nrow(df))
      m_bind_rows   = prop_named("bind_rows_doubles",    \(df) nrow(bind_rows(df, df)) == 2 * nrow(df))
      m_slice_min_n = prop_named("slice_min_size",       \(df) nrow(slice_min(df, $x, n = 2)) == to_integer(min([2, nrow(df)])))
      m_count_n     = prop_named("count_equals_distinct", \(df) nrow(count(df, $g)) == n_distinct(pull(df, "g")))
      m_uncount_n   = prop_named("uncount_weights_sum",  \(df) nrow(uncount(df, $w)) == sum(pull(df, "w")))
      m_relocate_first = prop_named("relocate_moves_col", \(df) get(colnames(relocate(df, $x)), 0) == "x")
      m_pivot_longer_n = prop_named("pivot_longer_single", \(df) nrow(pivot_longer(df, $x, names_to = "k", values_to = "v")) == nrow(df))
      m_replace_na_clean = prop_named("replace_na_removes", \(df) sum(ifelse(is_na(pull(replace_na(df, [x: 0]), "x")), 1, 0)) == 0)
    |} in

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
  let env = Test_helpers.eval_setup eval_string_env env "test_property_verbs:64" "mt = to_dataframe([x: [1, 2, 3], s: [\"a\", \"b\", \"c\"], f: to_factor([\"p\", \"q\", \"p\"])])" in
  let env = Test_helpers.eval_setup eval_string_env env "test_property_verbs:65" "mt2 = to_dataframe([x: [1, 1, 2, 2, 3], s: [\"z\", \"z\", \"z\", \"z\", \"z\"]])" in
  let date_df    = "prop_gen_df([d: prop_gen_ymd(2000, 2024), x: prop_gen_int_range(0, 100)], nrows = 30, na_prob = 0.3)" in
  let nan_df     = "prop_gen_df([f: prop_gen_one_of([to_float(\"NaN\"), 1.0, 2.0])], nrows = 20, na_prob = 0.0)" in
  let wt_df      = "prop_gen_df([w: prop_gen_int_range(1, 3)], nrows = 20, na_prob = 0.0)" in

  let seeds = [ 1; 7 ] in

  (* Row-preserving verbs *)
  Test_helpers.prop_test_seeded test_env env "mutate preserves nrow (float)" "m_mutate" float_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "mutate preserves nrow (int)" "m_mutate" int_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "arrange preserves nrow (float)" "m_arrange" float_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "arrange preserves nrow (int)" "m_arrange" int_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "filter output <= input (float)" "m_filter" float_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "filter output <= input (int)" "m_filter" int_df 25 seeds;

  (* Row-count algebra — 2 gens each *)
  Test_helpers.prop_test_seeded test_env env "group_by+summarize group sizes sum to nrow (factor)" "m_gsum" factor_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "group_by+summarize group sizes sum to nrow (str)" "m_gsum" str_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "distinct never grows rows (int_range)" "m_distinct" int_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "distinct never grows rows (str)" "m_distinct" str_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "head slices to fixed size (int_range)" "m_head" int_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "head slices to fixed size (str)" "m_head" str_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "slice_sample keeps requested size (int_range)" "m_slice" int_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "slice_sample keeps requested size (str)" "m_slice" str_df 25 seeds;

  (* stats verbs with na_rm *)
  Test_helpers.prop_test_seeded test_env env "mean with na_rm stays in range (float)" "m_mean" float_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "mean with na_rm stays in range (int)" "m_mean" int_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "sd with na_rm non-negative (float)" "m_sd" float_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "sd with na_rm non-negative (int)" "m_sd" int_df 25 seeds;

  (* joins against fixed lookup *)
  Test_helpers.prop_test_seeded test_env env "left_join preserves rows (factor)" "m_join" factor_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "left_join preserves rows (str)" "m_join" str_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "left_join preserves rows under NA keys (factor)" "m_join" fct_na_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "left_join preserves rows under NA keys (str)" "m_join" str_na_df 25 seeds;

  (* fill *)
  Test_helpers.prop_test_seeded test_env env "fill preserves nrow (factor+int)" "m_fill" fct_int_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "fill preserves nrow (str+float)" "m_fill" str_flt_df 25 seeds;

  (* bug-fix regressions: drop_na on date columns, NaN dedup, arrange idempotence *)
  Test_helpers.prop_test_seeded test_env env "drop_na never grows rows (date+int df)" "m_drop_na" date_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "drop_na on a date column never grows rows" "m_drop_na_d" date_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "arrange is idempotent (int df)" "m_arrange_id" int_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "arrange is idempotent (date df)" "m_arrange_id" date_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "rename preserves column count" "m_rename_col" float_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "mutate then select yields expected columns" "m_mutate_sel" float_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "distinct never grows rows (float df)" "m_distinct_nd" float_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "drop_na on NaN-injecting float column never grows rows" "m_drop_na_nan" nan_df 25 seeds;

  (* UTF-8 regex engine: multibyte values and Unicode letter classes *)
  let multibyte_df = "prop_gen_df([x: prop_gen_string_from(\"\u{00E9};\u{00E0}\u{00FC}\", 1, 8)], nrows = 30, na_prob = 0.0)" in
  let ascii_sep_df = "prop_gen_df([x: prop_gen_string_from(\"ab;cd\", 1, 8)], nrows = 30, na_prob = 0.0)" in
  Test_helpers.prop_test_seeded test_env env "matches supports Unicode letter classes (multibyte df)" "m_matches_ucp" multibyte_df 20 seeds;
  Test_helpers.prop_test_seeded test_env env "matches supports Unicode letter classes (ascii df)" "m_matches_ucp" ascii_sep_df 20 seeds;
  Test_helpers.prop_test_seeded test_env env "contains filters column names (multibyte df)" "m_contains_x" multibyte_df 20 seeds;
  Test_helpers.prop_test_seeded test_env env "contains filters column names (ascii df)" "m_contains_x" ascii_sep_df 20 seeds;
  Test_helpers.prop_test_seeded test_env env "separate_rows never shrinks rows (multibyte df)" "m_sep_nrow" multibyte_df 20 seeds;
  Test_helpers.prop_test_seeded test_env env "separate_rows never shrinks rows (ascii df)" "m_sep_nrow" ascii_sep_df 20 seeds;
  Test_helpers.prop_test_seeded test_env env "separate adds exactly one column (multibyte df)" "m_sep_ncol" multibyte_df 20 seeds;
  Test_helpers.prop_test_seeded test_env env "separate adds exactly one column (ascii df)" "m_sep_ncol" ascii_sep_df 20 seeds;

  (* schema-derived generator *)
  Test_helpers.prop_test_seeded test_env env "prop_gen_df_from round-trips mutate via macro" "m_df_from" df_from_gen 25 seeds;
  (* same macro, second generator: coarsen the df *)
  Test_helpers.prop_test_seeded test_env env "prop_gen_df_from round-trips mutate via macro (smaller schema)" "m_df_from" "prop_gen_df_from(mt2, nrows = 40, na_prob = 0.2)" 25 seeds;

  (* Hardened invariants *)
  Test_helpers.prop_test_seeded test_env env "select preserves nrow (float)" "m_select_nrow" float_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "distinct is idempotent (int df)" "m_distinct_idem" int_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "pull length equals nrow (int df)" "m_pull_len" int_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "full_join never loses rows (factor)" "m_full_join_ge" factor_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "bind_rows doubles rows (int df)" "m_bind_rows" int_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "slice_min returns min(n, nrow) rows (float)" "m_slice_min_n" float_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "count matches n_distinct of group (string)" "m_count_n" str_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "count matches n_distinct of group (factor)" "m_count_n" factor_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "uncount expands to the weight sum" "m_uncount_n" wt_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "relocate moves the column to the front" "m_relocate_first" fct_int_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "pivot_longer on one column preserves nrow" "m_pivot_longer_n" int_df 25 seeds;
  Test_helpers.prop_test_seeded test_env env "replace_na removes NAs from the target column" "m_replace_na_clean" int_df 25 seeds;

  Printf.printf "\n"
