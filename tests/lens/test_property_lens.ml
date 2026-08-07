(* Dogfooding: functional lens laws exercised via prop_named / prop_test over
   generated Dicts, Lists, and DataFrames. These codify the classic lens
   axioms — get-set, set-get, over = set∘get, and composition — plus the
   filter_lens annihilation law and DataFrame scalar-set laws. Each property
   runs under several fixed seeds via prop_test_seeded. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — lens:\n";
  let env = Packages.init_env () in

  let (_, env) =
    eval_string_env {|
      m_dict_get_set     = prop_named("dict_get_set",    \(d) get(set(d, col_lens("a"), d.b), col_lens("a")) == d.b)
      m_dict_set_get     = prop_named("dict_set_get",    \(d) identical(set(d, col_lens("a"), get(d, col_lens("a"))), d))
      m_dict_over_set    = prop_named("dict_over_set",   \(d) identical(over(d, col_lens("a"), \(x) x * 2), set(d, col_lens("a"), get(d, col_lens("a")) * 2)))
      m_dict_set_set     = prop_named("dict_set_set",    \(d) identical(set(set(d, col_lens("a"), d.b), col_lens("a"), 7), set(d, col_lens("a"), 7)))
      m_dict_compose     = prop_named("dict_compose",    \(d) get(d, compose(col_lens("outer"), col_lens("inner"))) == d.outer.inner)
      m_dict_modify      = prop_named("dict_modify",     \(d) identical(modify(d, col_lens("a"), \(x) x + 1, col_lens("b"), \(x) x * 2), set(set(d, col_lens("a"), get(d, col_lens("a")) + 1), col_lens("b"), get(d, col_lens("b")) * 2)))
      m_idx_get_set      = prop_named("idx_get_set",     \(xs) get(set(xs, idx_lens(get(xs, 0) % length(xs)), 777), idx_lens(get(xs, 0) % length(xs))) == 777)
      m_idx_set_get      = prop_named("idx_set_get",     \(xs) identical(set(xs, idx_lens(get(xs, 0) % length(xs)), get(xs, idx_lens(get(xs, 0) % length(xs)))), xs))
      m_flt_len          = prop_named("flt_len",         \(xs) length(get(xs, filter_lens(\(x) x > 5))) <= length(xs))
      m_flt_annihilate   = prop_named("flt_annihilate",  \(xs) length(get(set(xs, filter_lens(\(x) x > 5), 0), filter_lens(\(x) x > 5))) == 0)
      m_df_set_nrow      = prop_named("df_set_nrow",     \(df) nrow(set(df, col_lens("x"), 0)) == nrow(df))
      m_df_set_len       = prop_named("df_set_len",      \(df) length(pull(set(df, col_lens("x"), 0), "x")) == nrow(df))
      m_df_over_nrow     = prop_named("df_over_nrow",    \(df) nrow(over(df, col_lens("x"), \(v) v .* 2)) == nrow(df))
    |} env
  in

  let seeds = [ 1; 7; 42 ] in
  let df_seeds = [ 1; 7 ] in
  let dict_gen     = "prop_gen_dict([a: prop_gen_int_range(0, 100), b: prop_gen_int_range(0, 100)], na_prob = 0.0)" in
  let nested_gen   = "prop_gen_dict([outer: prop_gen_dict([inner: prop_gen_int_range(0, 100)], na_prob = 0.0)], na_prob = 0.0)" in
  let list_gen     = "prop_gen_list(prop_gen_int_range(1, 100), 4)" in
  let flt_list_gen = "prop_gen_list(prop_gen_int_range(0, 10), 8)" in
  let df_gen       = "prop_gen_df([x: prop_gen_int_range(0, 100)], nrows = 10, na_prob = 0.2)" in

  Test_helpers.prop_test_seeded test_env env "dict get-set law (set then get returns the value)" "m_dict_get_set" dict_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "dict set-get law (set to current value is identity)" "m_dict_set_get" dict_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "dict over equals set with the mapped value" "m_dict_over_set" dict_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "dict set-set law (later set wins)" "m_dict_set_set" dict_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "composed lens reads the nested field" "m_dict_compose" nested_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "modify applies lens-function pairs like chained sets" "m_dict_modify" dict_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "idx lens get-set law on lists" "m_idx_get_set" list_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "idx lens set-get law on lists" "m_idx_set_get" list_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "filter lens never grows the selection" "m_flt_len" flt_list_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "filter lens set annihilates the matched elements" "m_flt_annihilate" flt_list_gen 30 seeds;
  Test_helpers.prop_test_seeded test_env env "col lens scalar set preserves nrow on a DataFrame" "m_df_set_nrow" df_gen 20 df_seeds;
  Test_helpers.prop_test_seeded test_env env "col lens scalar set keeps the column length" "m_df_set_len" df_gen 20 df_seeds;
  Test_helpers.prop_test_seeded test_env env "col lens over preserves nrow on a DataFrame" "m_df_over_nrow" df_gen 20 df_seeds;

  Printf.printf "\n"
