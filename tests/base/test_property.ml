let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env _test test_env =
  Printf.printf "Popcraft — property-based testing:\n";
  let env = Packages.init_env () in

  (* PASS cases *)
  test_env env "prop_for_all PASS int"
    "prop_for_all(prop_gen_int_range(0, 0), \\(x) x == 0, n = 10)" "PASS";
  test_env env "prop_for_all PASS bool"
    "prop_for_all(prop_gen_bool(), \\(b) b == true || b == false, n = 20)" "PASS";
  test_env env "prop_for_all PASS list"
    "prop_for_all(prop_gen_list(prop_gen_bool(), 3), \\(xs) length(xs) == 3, n = 20)" "PASS";
  test_env env "prop_for_all PASS vector"
    "prop_for_all(prop_gen_vector(prop_gen_int_range(0, 100), 5), \\(xs) length(xs) == 5, n = 20)"
    "PASS";
  test_env env "prop_for_all PASS string"
    {|prop_for_all(prop_gen_string_from("ab", 1, 3), \(s) str_nchar(s) >= 1 && str_nchar(s) <= 3, n = 20)|}
    "PASS";
  test_env env "prop_for_all PASS factor"
    {|prop_for_all(prop_gen_factor(["a", "b"]), \(f) f == "a" || f == "b", n = 20)|} "PASS";
  test_env env "prop_for_all PASS choice"
    "prop_for_all(prop_gen_choice([prop_gen_int_range(0, 0), prop_gen_bool()]), \\(x) x == 0 || x == true || x == false, n = 20)"
    "PASS";
  test_env env "prop_for_all PASS map_gen"
    "prop_for_all(prop_map_gen(prop_gen_int_range(0, 5), \\(v) v * 2), \\(x) x % 2 == 0, n = 20)"
    "PASS";
  test_env env "prop_for_all PASS resize"
    "prop_for_all(prop_resize(prop_gen_int_range(0, 100), 5), \\(x) x >= 0, n = 20)" "PASS";
  test_env env "prop_for_all resize overrides vector length"
    "prop_for_all(prop_resize(prop_gen_vector(prop_gen_int_range(0, 0), 3), 5), \\(v) length(v) == 5, n = 10)"
    "PASS";
  test_env env "prop_for_all resize overrides df nrows"
    "prop_for_all(prop_resize(prop_gen_df([x: prop_gen_int_range(0, 0)], nrows = 3), 5), \\(df) nrow(df) == 5, n = 10)"
    "PASS";
  test_env env "prop_for_all PASS df nrows respected"
    "prop_for_all(prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 50), \\(df) nrow(df) == 50, n = 10)"
    "PASS";
  test_env env "prop_for_all PASS multi-byte string chars"
    "prop_for_all(prop_gen_string_from(\"\\xCE\\xBB\", 1, 1), \\(s) str_nchar(s) == 2, n = 5)"
    "PASS";

  (* FAIL cases *)
  test_env env "prop_for_all STOP on false"
    "set_seed(42)\nprop_for_all(prop_gen_int_range(0, 100), \\(x) x < 10, n = 20)" "STOP(";
  test_env env "prop_for_all deterministic counterexample"
    "set_seed(42)\nprop_for_all(prop_gen_int_range(0, 100), \\(x) x < 10, n = 20)"
    "counterexample: 54";
  test_env env "prop_for_all deterministic shrink"
    "set_seed(42)\nprop_for_all(prop_gen_int_range(0, 100), \\(x) x < 10, n = 20)"
    "(shrunk): 13";
  test_env env "prop_for_all NA predicate fails"
    "set_seed(1)\nprop_for_all(prop_gen_int_range(0, 5), \\(x) NA, n = 5)"
    "returned NA (property must handle missingness explicitly)";
  test_env env "prop_for_all error predicate fails"
    "set_seed(1)\nprop_for_all(prop_gen_int_range(0, 5), \\(x) error(\"boom\"), n = 5)"
    "raised: boom";
  test_env env "prop_for_all Expect_hold fails"
    "set_seed(1)\nprop_for_all(prop_gen_int_range(0, 5), \\(x) expect_equal(NA, 1), n = 5)"
    "failed: `actual` is NA, cannot compare";
  test_env env "prop_for_all non-function property fails"
    "set_seed(1)\nprop_for_all(prop_gen_int_range(0, 5), 42, n = 5)" "STOP(";
  test_env env "prop_for_all shrink=false still reports"
    "set_seed(42)\nprop_for_all(prop_gen_int_range(0, 100), \\(x) x < 10, n = 5, shrink = false)"
    "predicate: returned false";
  test_env env "prop_for_all reproducible across runs"
    "set_seed(42)\na = prop_for_all(prop_gen_int_range(0, 100), \\(x) x < 10, n = 20)\nset_seed(42)\nb = prop_for_all(prop_gen_int_range(0, 100), \\(x) x < 10, n = 20)\na == b"
    "true";

  (* df NA injection *)
  test_env env "prop_gen_df NA injection renders NA"
    "set_seed(7)\nprop_for_all(prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 30, na_prob = 1.0), \\(df) false, n = 1)"
    "NA(Float)";
  test_env env "prop_gen_df factor NA renders typed"
    "set_seed(7)\nprop_for_all(prop_gen_df([grp: prop_gen_factor([\"a\", \"b\"])], nrows = 10, na_prob = 1.0), \\(df) false, n = 1)"
    "NA(String)";
  test_env env "prop_gen_df mixed factor + NA builds"
    "prop_for_all(prop_gen_df([grp: prop_gen_factor([\"a\", \"b\"])], nrows = 10, na_prob = 0.5), \\(df) nrow(df) == 10, n = 5)"
    "PASS";

  (* Generator / combinator validation *)
  test_env env "prop_such_that exhaustion fails"
    "prop_for_all(prop_such_that(prop_gen_int_range(0, 0), \\(x) x == 1), \\(x) true, n = 5)"
    "prop_such_that: predicate could not be satisfied";
  test_env env "prop_for_all n must be positive"
    "prop_for_all(prop_gen_int(), \\(x) true, n = 0)"
    "expects `n` to be a positive Int";
  test_env env "prop_for_all unknown named arg"
    "prop_for_all(prop_gen_int(), \\(x) true, n = 5, bogus = 1)"
    "received unknown named argument `bogus`";
  test_env env "prop_gen_int_range max below min errors"
    "prop_gen_int_range(5, 1)"
    "requires max >= min, got [5, 1]";
  test_env env "prop_gen_float_range max equal min errors"
    "prop_gen_float_range(1.0, 1.0)"
    "requires max > min";
  test_env env "prop_gen_choice empty errors"
    "prop_gen_choice([])"
    "expects a non-empty list of generators";
  test_env env "prop_gen_frequency empty errors"
    "prop_gen_frequency([])"
    "expects a non-empty list";
  test_env env "prop_gen_df non-dict columns errors"
    "prop_gen_df([])"
    "expects `columns` to be a Dict, got List";
  test_env env "prop_gen_string_from empty chars errors"
    {|prop_gen_string_from("", 0, 0)|}
    "expects a non-empty set of characters";
  test_env env "prop_gen_int unknown named arg errors"
    "prop_gen_int(bogus = 1)"
    "received unknown named argument `bogus`";

  (* assert integration — how prop_for_all is used inside `t test` files *)
  test_env env "assert around passing prop_for_all"
    "set_seed(42)\nassert(prop_for_all(prop_gen_int_range(0, 100), \\(x) x >= 0, n = 20))"
    "true";
  test_env env "assert around failing prop_for_all raises"
    "set_seed(42)\nassert(prop_for_all(prop_gen_int_range(0, 100), \\(x) x < 10, n = 20))"
    "Assertion failed: Property failed after";

  (* generator specs are inspectable dicts *)
  test_env env "generator spec is structured dict"
    "prop_gen_int_range(1, 5)"
    "{`gen`: \"int_range\", `min`: 1, `max`: 5}";

  Printf.printf "\n"
