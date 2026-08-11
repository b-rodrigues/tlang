(* Dogfooding: testcraft package invariants exercised via prop_named / prop_test
   over generated values. Covers expect_equal identity over scalars and DataFrames,
   expect_fail on unequal values, expect_nrow/ncol/colnames, expect_length,
   expect_true/false, expect_between, expect_set_equal, expect_unique,
   expect_no_na, and expect_str_contains. *)
let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — testcraft:\n";
  let env = Packages.init_env () in

  let _ = eval_string_env "set_seed(1)" env in

  (* ---- expect_equal identity over generated scalars ---- *)

  test_env env "expect_equal identity Int"
    {|prop_for_all(prop_gen_int_range(-1000, 1000), \(x) expect_pass(expect_equal(x, x)), n = 30)|} "PASS";

  test_env env "expect_equal identity Float"
    {|prop_for_all(prop_gen_float_range(-100.0, 100.0), \(x) expect_pass(expect_equal(x, x)), n = 30)|} "PASS";

  test_env env "expect_equal identity Bool"
    {|prop_for_all(prop_gen_bool(), \(x) expect_pass(expect_equal(x, x)), n = 10)|} "PASS";

  test_env env "expect_equal identity String"
    {|prop_for_all(prop_gen_string_from("abcdefghijklmnopqrstuvwxyz", 0, 20), \(x) expect_pass(expect_equal(x, x)), n = 30)|} "PASS";

  (* ---- expect_equal on NA holds (not stops) ---- *)

  test_env env "expect_equal NA vs value returns Expect_hold"
    {|expect_msg(expect_equal(na(), 42))|} "NA";

  test_env env "expect_equal value vs NA returns Expect_hold"
    {|expect_msg(expect_equal(42, na()))|} "NA";

  (* ---- expect_equal detects difference ---- *)

  test_env env "expect_equal non-equal Ints fail"
    {|expect_fail(expect_equal(1, 2))|} "true";

  test_env env "expect_equal non-equal Floats fail"
    {|expect_fail(expect_equal(1.0, 2.0))|} "true";

  test_env env "expect_equal non-equal Bool fails"
    {|expect_fail(expect_equal(true, false))|} "true";

  test_env env "expect_equal non-equal Strings fail"
    {|expect_fail(expect_equal("hello", "world"))|} "true";

  test_env env "expect_equal generated Int vs Int+1 fails"
    {|prop_for_all(prop_gen_int_range(-100, 100), \(x) expect_fail(expect_equal(x, x + 1)), n = 20)|} "PASS";

  (* ---- expect_equal with Float tolerance ---- *)

  test_env env "expect_equal Float tolerance passes near values"
    {|expect_pass(expect_equal(1.0, 1.000000001, tolerance = 1e-8))|} "true";

  test_env env "expect_equal Float tolerance fails far values"
    {|expect_fail(expect_equal(1.0, 1.01, tolerance = 1e-8))|} "true";

  (* ---- expect_equal DataFrame identity ---- *)

  test_env env "expect_equal DataFrame identity"
    {|prop_for_all(prop_gen_df([x: prop_gen_int_range(0, 100), s: prop_gen_one_of(["a", "b"])], nrows = 20, na_prob = 0.1), \(df) expect_pass(expect_equal(df, df)), n = 10)|} "PASS";

  test_env env "expect_equal List identity"
    {|prop_for_all(prop_gen_list(prop_gen_int_range(0, 100), 5), \(l) expect_pass(expect_equal(l, l)), n = 10)|} "PASS";

  test_env env "expect_equal Vector identity"
    {|prop_for_all(prop_gen_vector(prop_gen_float_range(0.0, 100.0), 5), \(v) expect_pass(expect_equal(v, v)), n = 10)|} "PASS";

  (* ---- expect_nrow / expect_ncol over generated DataFrames ---- *)

  test_env env "expect_nrow matches generated DataFrame rows"
    {|prop_for_all(prop_gen_df([x: prop_gen_int_range(0, 10)], nrows = 15, na_prob = 0.0), \(df) expect_pass(expect_nrow(df, nrow(df))), n = 10)|} "PASS";

  test_env env "expect_ncol matches generated DataFrame columns"
    {|prop_for_all(prop_gen_df([x: prop_gen_int_range(0, 10), y: prop_gen_float_range(0.0, 10.0)], nrows = 10, na_prob = 0.0), \(df) expect_pass(expect_ncol(df, ncol(df))), n = 10)|} "PASS";

  test_env env "expect_nrow detects mismatch"
    {|expect_fail(expect_nrow(to_dataframe([x: [1, 2, 3]]), 99))|} "true";

  test_env env "expect_ncol detects mismatch"
    {|expect_fail(expect_ncol(to_dataframe([x: [1]]), 99))|} "true";

  (* ---- expect_length over generated vectors/lists ---- *)

  test_env env "expect_length Vector identity"
    {|prop_for_all(prop_gen_vector(prop_gen_int_range(0, 10), 7), \(v) expect_pass(expect_length(v, length(v))), n = 10)|} "PASS";

  test_env env "expect_length List identity"
    {|prop_for_all(prop_gen_list(prop_gen_int_range(0, 10), 7), \(l) expect_pass(expect_length(l, length(l))), n = 10)|} "PASS";

  test_env env "expect_length detects mismatch"
    {|expect_fail(expect_length([1, 2, 3], 99))|} "true";

  (* ---- expect_true / expect_false ---- *)

  test_env env "expect_true passes on true"
    {|expect_pass(expect_true(true))|} "true";

  test_env env "expect_true fails on false"
    {|expect_fail(expect_true(false))|} "true";

  test_env env "expect_false passes on false"
    {|expect_pass(expect_false(false))|} "true";

  test_env env "expect_false fails on true"
    {|expect_fail(expect_false(true))|} "true";

  test_env env "expect_true holds on NA"
    {|expect_msg(expect_true(na()))|} "is NA, cannot check truth";

  test_env env "expect_false holds on NA"
    {|expect_msg(expect_false(na()))|} "is NA, cannot check falsity";

  (* ---- expect_between over generated values ---- *)

  test_env env "expect_between passes for in-range values"
    {|prop_for_all(prop_gen_int_range(0, 100), \(x) expect_pass(expect_between(x, 0, 100)), n = 30)|} "PASS";

  test_env env "expect_between fails for out-of-range"
    {|expect_fail(expect_between(-1, 0, 100))|} "true";

  test_env env "expect_between holds on NA"
    {|expect_msg(expect_between(na(), 0, 100))|} "NA";

  (* ---- expect_set_equal over generated lists ---- *)

  test_env env "expect_set_equal identity"
    {|prop_for_all(prop_gen_list(prop_gen_int_range(0, 20), 5), \(l) expect_pass(expect_set_equal(l, l)), n = 10)|} "PASS";

  test_env env "expect_set_equal order-independent"
    {|expect_pass(expect_set_equal([1, 2, 3], [3, 2, 1]))|} "true";

  test_env env "expect_set_equal detects extra element"
    {|expect_fail(expect_set_equal([1, 2], [1, 2, 3]))|} "true";

  (* ---- expect_unique over generated vectors ---- *)

  test_env env "expect_unique passes for all-unique"
    {|prop_for_all(prop_gen_vector(prop_gen_int_range(0, 1000), 5), \(v) expect_pass(expect_unique(v)), n = 20)|} "PASS";

  test_env env "expect_unique fails for duplicates"
    {|expect_fail(expect_unique([1, 1, 2, 3]))|} "true";

  test_env env "expect_unique passes for empty vector"
    {|expect_pass(expect_unique([]))|} "true";

  (* ---- expect_no_na over generated DataFrames ---- *)

  test_env env "expect_no_na passes on clean DF"
    {|prop_for_all(prop_gen_df([x: prop_gen_int_range(0, 100)], nrows = 10, na_prob = 0.0), \(df) expect_pass(expect_no_na(df)), n = 10)|} "PASS";

  test_env env "expect_no_na detects NA in column"
    {|df = to_dataframe([x: [1, na_int(), 3]]); expect_fail(expect_no_na(df))|} "true";

  test_env env "expect_no_na holds on NA DataFrame"
    {|expect_msg(expect_no_na(na()))|} "Value is NA";

  (* ---- expect_str_contains ---- *)

  test_env env "expect_str_contains identity"
    {|prop_for_all(prop_gen_string_from("abc", 1, 10), \(s) expect_pass(expect_str_contains(s, s)), n = 20)|} "PASS";

  test_env env "expect_str_contains empty substring always passes"
    {|prop_for_all(prop_gen_string_from("abc", 0, 10), \(s) expect_pass(expect_str_contains(s, "")), n = 20)|} "PASS";

  test_env env "expect_str_contains detects absence"
    {|expect_fail(expect_str_contains("abc", "xyz"))|} "true";

  (* ---- expect_fields over generated Dicts ---- *)

  test_env env "expect_fields matches generated Dict keys"
    {|prop_for_all(prop_gen_dict([x: prop_gen_int_range(0, 5), s: prop_gen_one_of(["a", "b"])], na_prob = 0.0), \(d) expect_pass(expect_fields(d, ["x", "s"])), n = 10)|} "PASS";

  (* ---- expect_in ---- *)

  test_env env "expect_in passes for member"
    {|prop_for_all(prop_gen_int_range(0, 10), \(x) expect_pass(expect_in(x, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])), n = 20)|} "PASS";

  test_env env "expect_in fails for non-member"
    {|expect_fail(expect_in(999, [1, 2, 3]))|} "true";

  (* ---- expect_match ---- *)

  test_env env "expect_match identity on generated strings over characters"
    {|expect_pass(expect_match("hello", "hello"))|} "true";

  test_env env "expect_match detects mismatch"
    {|expect_fail(expect_match("abc", "^\\\\d+$"))|} "true";

  (* ---- expect_summary ---- *)

  test_env env "expect_summary produces DataFrame"
    {|s = expect_summary([expect_equal(1, 1), expect_equal(2, 3)]); nrow(s) == 2 && ncol(s) >= 2|} "true";

  Printf.printf "\n"
