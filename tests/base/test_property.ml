let run_tests pass_count fail_count _failures _eval_string _eval_string_env _test test_env =
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
  test_env env "prop_for_all resize propagates through choice"
    "prop_for_all(prop_resize(prop_gen_choice([prop_gen_vector(prop_gen_int_range(0, 0), 3), prop_gen_vector(prop_gen_int_range(1, 1), 7)]), 5), \\(v) length(v) == 5, n = 10)"
    "PASS";
  test_env env "prop_for_all PASS df nrows respected"
    "prop_for_all(prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 50), \\(df) nrow(df) == 50, n = 10)"
    "PASS";
  test_env env "prop_for_all PASS multi-byte string chars"
    "prop_for_all(prop_gen_string_from(\"\\xCE\\xBB\", 1, 1), \\(s) s == \"\\xCE\\xBB\", n = 5)"
    "PASS";
  test_env env "prop_for_all PASS one_of ints"
    "prop_for_all(prop_gen_one_of([10, 20, 30]), \\(v) v == 10 || v == 20 || v == 30, n = 30)"
    "PASS";
  test_env env "prop_for_all PASS one_of strings"
    "prop_for_all(prop_gen_one_of([\"a\", \"b\"]), \\(s) s == \"a\" || s == \"b\", n = 30)"
    "PASS";
  test_env env "prop_for_all PASS one_of dates"
    "prop_for_all(prop_gen_one_of([ymd(\"2020-01-01\"), ymd(\"2021-01-01\")]), \\(d) year(d) == 2020 || year(d) == 2021, n = 20)"
    "PASS";
  test_env env "prop_for_all PASS date_range"
    "prop_for_all(prop_gen_date_range(ymd(\"2020-01-01\"), ymd(\"2020-12-31\")), \\(d) year(d) == 2020, n = 30)"
    "PASS";
  test_env env "prop_for_all PASS date_range inclusive endpoints"
    "set_seed(7)\nprop_for_all(prop_gen_date_range(ymd(\"2020-01-01\"), ymd(\"2020-01-01\")), \\(d) d == ymd(\"2020-01-01\"), n = 5)"
    "PASS";
  test_env env "prop_for_all PASS datetime_range"
    "prop_for_all(prop_gen_date_range(ymd_hms(\"2020-06-01 00:00:00\"), ymd_hms(\"2020-06-01 23:59:59\")), \\(d) year(d) == 2020 && month(d) == 6, n = 30)"
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

  (* DataFrame shrinking *)
  test_env env "prop_for_all shrinks df rows to empty frame"
    "set_seed(7)\nprop_for_all(prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 30, na_prob = 0.0), \\(df) false, n = 1)"
    "DataFrame(0 rows x 1 cols)";
  test_env env "prop_for_all minimizes df cells"
    "set_seed(3)\nprop_for_all(prop_gen_df([x: prop_gen_int_range(1, 5), s: prop_gen_string_from(\"abc\", 1, 3)], nrows = 30, na_prob = 0.0), \\(df) nrow(df) < 30, n = 1)"
    "<Int> 0, 0, 0, 0, 0, 0, 0, 0";
  test_env env "prop_for_all minimizes df string cells"
    "set_seed(3)\nprop_for_all(prop_gen_df([x: prop_gen_int_range(1, 5), s: prop_gen_string_from(\"abc\", 1, 3)], nrows = 30, na_prob = 0.0), \\(df) nrow(df) < 30, n = 1)"
    "<String> \"\", \"\", \"\", \"\", \"\", \"\", \"\", \"\"";

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
  test_env env "prop_gen_one_of empty list errors"
    "prop_gen_one_of([])"
    "expects a non-empty List or Vector of values";
  test_env env "prop_gen_one_of non-list errors"
    "prop_gen_one_of(1)"
    "expects a List or Vector, got Int";
  test_env env "prop_gen_date_range inverted bounds errors"
    "prop_gen_date_range(ymd(\"2020-01-01\"), ymd(\"2019-01-01\"))"
    "requires `end` to be on or after `start`";
  test_env env "prop_gen_date_range inverted datetime bounds errors"
    "prop_gen_date_range(ymd_hms(\"2020-06-02 00:00:00\"), ymd_hms(\"2020-06-01 00:00:00\"))"
    "requires `end` to be on or after `start`";
  test_env env "prop_gen_date_range mixed date/datetime errors"
    "prop_gen_date_range(ymd(\"2020-01-01\"), ymd_hms(\"2020-01-01 00:00:00\"))"
    "both bounds to be Dates or both to be Datetimes";
  test_env env "prop_gen_date_range non-date bounds errors"
    "prop_gen_date_range(ymd(\"2020-01-01\"), 1)"
    "expects Date or Datetime bounds, got Date and Int";

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

  (* with_seed — scoped RNG determinism *)
  test_env env "with_seed scopes RNG, outer stream unaffected"
    "set_seed(42)\na = sample([1, 2, 3, 4, 5], n = 3)\nset_seed(42)\nx = with_seed(1, \\(u) sample([1, 2, 3, 4, 5], n = 3))\nb = sample([1, 2, 3, 4, 5], n = 3)\nidentical(a, b)"
    "true";
  test_env env "with_seed is deterministic"
    "identical(with_seed(42, \\(u) sample([1, 2, 3, 4, 5], n = 3)), with_seed(42, \\(u) sample([1, 2, 3, 4, 5], n = 3)))"
    "true";
  test_env env "with_seed nests and restores inner seed"
    "identical(with_seed(1, \\(u) with_seed(2, \\(v) sample([1, 2, 3, 4, 5], n = 3))), with_seed(2, \\(u) sample([1, 2, 3, 4, 5], n = 3)))"
    "true";
  test_env env "with_seed propagates thunk error"
    "with_seed(1, \\(u) error(\"boom\"))"
    "boom";
  test_env env "with_seed non-int seed errors"
    "with_seed(\"42\", \\(u) 1)"
    "expects an integer seed";
  test_env env "with_seed accepts named function() thunks"
    "identical(with_seed(7, function(u) sample([1, 2, 3, 4, 5], n = 3)), with_seed(7, \\(u) sample([1, 2, 3, 4, 5], n = 3)))"
    "true";
  test_env env "with_seed non-function thunk errors"
    "with_seed(42, 1)"
    "Value of type Int is not callable.";
  test_env env "with_seed NA seed errors"
    "with_seed(NA, \\(u) 1)"
    "expects an integer seed";

  (* with_seed — restore RNG after an exception escapes the thunk *)
  let test_restore_after_error pass_count fail_count =
    Rng.set_seed 1;
    let before = Rng.sample_indices ~total:5 ~k:3 ~replace:false in
    Rng.set_seed 1;
    (match Rng.with_seed 99 (fun () -> failwith "boom") with
     | _ -> ()
     | exception _ -> ());
    let after = Rng.sample_indices ~total:5 ~k:3 ~replace:false in
    if before = after then begin
      incr pass_count;
      Printf.printf "  ✓ with_seed restores RNG state after thunk exception\n"
    end else begin
      incr fail_count;
      Printf.printf "  ✗ with_seed restores RNG state after thunk exception\n"
    end
  in
  test_restore_after_error pass_count fail_count;

  Printf.printf "\n"
