let run_tests pass_count fail_count failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft — property-based testing:\n";
  let env = Packages.init_env () in

  (* prop_show_spec round-trip: the rendered T source must rebuild a
     behaviorally equivalent generator — identical draws under the same
     seed. *)
  let assert_roundtrip label preamble spec_expr =
    let (_, env1) =
      eval_string_env (Printf.sprintf "set_seed(42)\n%s\norig = %s" preamble spec_expr) env
    in
    let (src_v, _) = eval_string_env "prop_show_spec(orig)" env1 in
    match src_v with
    | Ast.VError err ->
        incr fail_count;
        failures :=
          Printf.sprintf "  ✗ %s\n    prop_show_spec raised: %s\n" label err.message
          :: !failures;
        Printf.printf "  ✗ %s (prop_show_spec: %s)\n" label err.message
    | VString rendered ->
        let (_, env2) =
          eval_string_env (Printf.sprintf "set_seed(42)\nrebuilt = %s" rendered) env1
        in
        let orig = match Ast.Env.find_opt "orig" env1 with Some v -> v | None -> Ast.VNA Ast.NAGeneric in
        let rebuilt = match Ast.Env.find_opt "rebuilt" env2 with Some v -> v | None -> Ast.VNA Ast.NAGeneric in
        let draws spec =
          Rng.set_seed 42;
          let rec go i acc =
            if i >= 20 then List.rev acc
            else
              match
                T_prop_for_all.draw_value ~eval_call:Eval.eval_call_immutable
                  ~env ~size:30 spec
              with
              | Ok v -> go (i + 1) (Propcraft_utils.render_value v :: acc)
              | Error e -> go (i + 1) (("<error: " ^ Ast.Utils.value_to_string e ^ ">") :: acc)
          in
          go 0 []
        in
        if draws orig = draws rebuilt then begin
          incr pass_count;
          Printf.printf "  ✓ %s\n" label
        end else begin
          incr fail_count;
          failures :=
            Printf.sprintf "  ✗ %s\n    seeded streams differ (rendered: %s)\n" label rendered
            :: !failures;
          Printf.printf "  ✗ %s (rendered: %s)\n" label rendered
        end
    | other ->
        incr fail_count;
        failures :=
          Printf.sprintf "  ✗ %s\n    unexpected prop_show_spec result: %s\n" label
            (Ast.Utils.value_to_string other)
          :: !failures;
        Printf.printf "  ✗ %s (unexpected result)\n" label
  in

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
  test_env env "prop_for_all PASS prop_gen_ymd year span"
    "prop_for_all(prop_gen_ymd(2000, 2024), \\(d) year(d) >= 2000 && year(d) <= 2024, n = 30)"
    "PASS";
  test_env env "prop_for_all PASS prop_gen_ymd inclusive single year"
    "set_seed(7)\nprop_for_all(prop_gen_ymd(2020, 2020), \\(d) year(d) == 2020, n = 5)"
    "PASS";
  test_env env "prop_for_all PASS prop_gen_ymd bounds respected"
    "prop_for_all(prop_gen_ymd(2000, 2024), \\(d) d >= ymd(\"2000-01-01\") && d <= ymd(\"2024-12-31\"), n = 30)"
    "PASS";
  test_env env "prop_gen_ymd df column with NA injection"
    "prop_for_all(prop_gen_df([d: prop_gen_ymd(2000, 2024)], nrows = 40, na_prob = 0.5), \\(df) nrow(df) == 40 && ncol(df) == 1, n = 5)"
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
  test_env env "prop_for_all max_counterexamples shows several"
    "set_seed(42)\nprop_for_all(prop_gen_int_range(0, 100), \\(x) x < 10, n = 20, max_counterexamples = 3)"
    "showing 3 counterexamples";
  test_env env "prop_for_all max_counterexamples numbers blocks"
    "set_seed(42)\nprop_for_all(prop_gen_int_range(0, 100), \\(x) x < 10, n = 20, max_counterexamples = 3)"
    "counterexample #1: 54";
  test_env env "prop_for_all max_counterexamples dedupes repeats"
    "set_seed(42)\nprop_for_all(prop_gen_int_range(5, 5), \\(x) false, n = 10, max_counterexamples = 3)"
    "Property failed after 10 of 10 runs (showing 1 counterexample).\n  counterexample #1: 5\n  (shrunk): 0\n  predicate: returned false";
  test_env env "prop_for_all max_counterexamples must be positive"
    "prop_for_all(prop_gen_int_range(0, 5), \\(x) true, n = 10, max_counterexamples = 0)"
    "expects `max_counterexamples` to be a positive Int";

  (* Wide / full int ranges previously crashed: Random.State.int only
     accepts bounds below 2^30, so wide spans must go through the int64
     rejection-sampling path (src/rng.ml). *)
  test_env env "prop_for_all wide int range stays in bounds"
    "set_seed(7)\nprop_for_all(prop_gen_int_range(-1000000000, 1000000000), \\(x) x >= -1000000000 && x <= 1000000000, n = 50)"
    "PASS";
  test_env env "prop_for_all full int span does not crash"
    "set_seed(7)\nprop_for_all(prop_gen_int_range(-2147483648, 2147483647), \\(x) x == x, n = 50)"
    "PASS";

  (* Shrinking a list/vector/dict containing a function used to raise
     Invalid_argument ("compare: functional value") inside List.sort_uniq
     and crash the process; now the prefix shrink drops the closure element
     instead. *)
  test_env env "prop_for_all closure in generated list does not crash shrink"
    "set_seed(3)\nprop_for_all(prop_map_gen(prop_gen_int_range(0, 5), \\(v) [v, \\(x) x]), \\(l) false, n = 5)"
    "counterexample: [";

  (* one_of shrinks within the provided values instead of toward 0. *)
  test_env env "prop_for_all one_of shrinks within values"
    "set_seed(9)\nprop_for_all(prop_gen_one_of([10, 20, 30, 40, 50]), \\(x) false, n = 5)"
    "(shrunk): 10";
  test_env env "prop_for_all one_of date shrinks within values"
    "set_seed(5)\nprop_for_all(prop_gen_one_of([make_date(year = 2024, month = 1, day = 1), make_date(year = 2024, month = 6, day = 1), make_date(year = 2024, month = 12, day = 1)]), \\(d) false, n = 5)"
    "Date(2024-01-01)";

  (* A mapping function that raises surfaces its VError instead of being
     swallowed as a drawn value. *)
  test_env env "prop_for_all map fn error surfaces cleanly"
    "set_seed(3)\nprop_for_all(prop_map_gen(prop_gen_int_range(0, 5), \\(v) missing_fn_xyz(v)), \\(x) true, n = 5)"
    "NameError";

  (* Datetime shrink uses int64-safe halving, so counterexamples render
     without truncation artifacts. *)
  test_env env "prop_for_all datetime ymd shrink works"
    "set_seed(4)\nprop_for_all(prop_gen_ymd(2024, 2025), \\(d) false, n = 5)"
    "counterexample";


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
  test_env env "prop_gen_df large batch draw smoke test"
    "prop_for_all(prop_gen_df([a: prop_gen_int_range(0, 100), b: prop_gen_float_range(0.0, 100.0), c: prop_gen_string_from(\"abc\", 1, 3), d: prop_gen_bool(), e: prop_gen_factor([\"x\", \"y\"])], nrows = 1000, na_prob = 0.1), \\(df) nrow(df) == 1000 && ncol(df) == 5, n = 5)"
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
  test_env env "prop_for_all shrinks date to year-span floor"
    "set_seed(1)\nprop_for_all(prop_gen_ymd(2000, 2024), \\(d) d >= ymd(\"2010-01-01\"), n = 30)"
    "Date(2000-01-01)";
  test_env env "prop_for_all shrinks date_range to start bound"
    "set_seed(1)\nprop_for_all(prop_gen_date_range(ymd(\"2000-01-01\"), ymd(\"2024-12-31\")), \\(d) d >= ymd(\"2010-01-01\"), n = 30)"
    "Date(2000-01-01)";
  test_env env "prop_for_all shrinks datetime to start bound"
    "set_seed(1)\nprop_for_all(prop_gen_date_range(ymd_hms(\"2020-01-01 00:00:00\"), ymd_hms(\"2024-12-31 23:59:59\")), \\(dt) dt >= ymd_hms(\"2022-06-01 00:00:00\"), n = 30)"
    "Datetime(2020-01-01T00:00:00Z)";
  test_env env "prop_for_all shrinks date in a df column"
    "set_seed(1)\nprop_for_all(prop_gen_df([d: prop_gen_ymd(2000, 2024)], nrows = 20, na_prob = 0.0), \\(df) false, n = 1)"
    "DataFrame(0 rows x 1 cols)";
  test_env env "prop_for_all shrinks df date cell to column floor"
    "set_seed(1)\nprop_for_all(prop_gen_df([d: prop_gen_ymd(2000, 2024)], nrows = 1, na_prob = 0.0), \\(df) nrow(df) == 0 || nrow(filter(df, \\(r) r.d >= ymd(\"2025-01-01\"))) == 1, n = 1)"
    "Date(2000-01-01)";
  test_env env "prop_for_all shrinks df date_range cell to start bound"
    "set_seed(1)\nprop_for_all(prop_gen_df([d: prop_gen_date_range(ymd(\"2020-01-01\"), ymd(\"2024-12-31\"))], nrows = 1, na_prob = 0.0), \\(df) nrow(df) == 0 || nrow(filter(df, \\(r) r.d >= ymd(\"2025-01-01\"))) == 1, n = 1)"
    "Date(2020-01-01)";
  test_env env "prop_for_all shrinks df datetime cell to start bound"
    "set_seed(1)\nprop_for_all(prop_gen_df([dt: prop_gen_date_range(ymd_hms(\"2020-01-01 00:00:00\"), ymd_hms(\"2024-12-31 23:59:59\"))], nrows = 1, na_prob = 0.0), \\(df) nrow(df) == 0 || nrow(filter(df, \\(r) r.dt >= ymd_hms(\"2025-01-01 00:00:00\"))) == 1, n = 1)"
    "Datetime(2020-01-01";

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
  test_env env "prop_gen_ymd inverted years errors"
    "prop_gen_ymd(2024, 2000)"
    "requires `max_year` to be on or after `min_year`";
  test_env env "prop_gen_ymd non-int bounds errors"
    "prop_gen_ymd(\"2000\", 2024)"
    "expects Int year bounds, got String and Int";
  test_env env "prop_gen_ymd arity error"
    "prop_gen_ymd(2000)"
    "expects 2 arguments but received 1";
  test_env env "prop_gen_ymd spec is inspectable dict"
    "prop_gen_ymd(2000, 2024)"
    "{`gen`: \"ymd_range\", `min_year`: 2000, `max_year`: 2024, `start_day`: 10957, `end_day`: 20088}";

  (* prop_gen_df_from — schema-derived generators *)
  test_env env "prop_gen_df_from round-trips nrows and columns"
    "mt = to_dataframe([x: [1, 2, 3], s: [\"a\", \"b\", \"c\"]])\nprop_for_all(prop_gen_df_from(mt, nrows = 10), \\(df) nrow(df) == 10 && ncol(df) == 2, n = 5)"
    "PASS";
  test_env env "prop_gen_df_from infers int column"
    "prop_gen_df_from(to_dataframe([x: [1, 2, 3]]))"
    "{`gen`: \"int_range\", `min`: 1, `max`: 3}";
  test_env env "prop_gen_df_from infers float column"
    "prop_gen_df_from(to_dataframe([y: [1.5, 2.5]]))"
    "{`gen`: \"float_range\", `min`: 1.5, `max`: 2.5}";
  test_env env "prop_gen_df_from constant float uses one_of"
    "prop_gen_df_from(to_dataframe([c: [2.0, 2.0]]))"
    "{`gen`: \"one_of\", `values`: [2.]}";
  test_env env "prop_gen_df_from infers string distinct values"
    "prop_gen_df_from(to_dataframe([s: [\"a\", \"b\", \"a\"]]))"
    "{`gen`: \"one_of\", `values`: [\"a\", \"b\"]}";
  test_env env "prop_gen_df_from infers factor levels"
    "prop_gen_df_from(to_dataframe([f: to_factor([\"b\", \"a\", \"b\"])]))"
    "{`gen`: \"factor\", `levels`: [\"a\", \"b\"]}";
  test_env env "prop_gen_df_from infers date range"
    "prop_gen_df_from(to_dataframe([d: [ymd(\"2020-01-01\"), ymd(\"2020-01-02\")]]))"
    "{`gen`: \"date_range\", `mode`: \"date\", `start_day`: 18262, `end_day`: 18263}";
  test_env env "prop_gen_df_from infers datetime range"
    "prop_gen_df_from(to_dataframe([dt: [ymd_hms(\"2020-06-01 00:00:00\"), ymd_hms(\"2020-06-01 12:00:00\")]]))"
    "{`gen`: \"date_range\", `mode`: \"datetime\"";
  test_env env "prop_gen_df_from infers bool column"
    "prop_gen_df_from(to_dataframe([b: [true, false]]))"
    "{`gen`: \"bool\"}";
  test_env env "prop_gen_df_from mixed-schema round-trip"
    "dd = to_dataframe([x: [1, 2, 3], f: to_factor([\"b\", \"a\", \"b\"]), d: [ymd(\"2020-01-01\"), ymd(\"2020-01-02\"), ymd(\"2021-06-15\")], b: [true, false, true]])\nprop_for_all(prop_gen_df_from(dd, nrows = 10), \\(df) nrow(df) == 10 && ncol(df) == 4, n = 5)"
    "PASS";
  test_env env "prop_gen_df_from NA-only column errors"
    "prop_gen_df_from(to_dataframe([x: [NA, NA]]))"
    "cannot infer a type for column `x`: no non-NA values";
  test_env env "prop_gen_df_from empty df errors"
    "prop_gen_df_from(to_dataframe([]))"
    "expects a DataFrame with at least one column";
  test_env env "prop_gen_df_from non-dataframe errors"
    "prop_gen_df_from(1)"
    "expects a DataFrame, got Int";
  test_env env "prop_gen_df_from unknown named arg errors"
    "prop_gen_df_from(to_dataframe([x: [1]]), bogus = 1)"
    "received unknown named argument `bogus`";
  test_env env "prop_gen_df_from unsupported column type errors"
    "prop_gen_df_from(to_dataframe([x: [to_dataframe([y: [1]]), to_dataframe([y: [2]])]]))"
    "unsupported value type DataFrame";

  (* prop_gen_fn — custom function generators *)
  test_env env "prop_for_all PASS custom fn generator"
    "prop_for_all(prop_gen_fn(\\(n) n * 2), \\(v) v % 2 == 0 && v >= 0, n = 20)"
    "PASS";
  test_env env "prop_gen_fn receives default size"
    "prop_for_all(prop_gen_fn(\\(n) n), \\(v) v == 30, n = 5)"
    "PASS";
  test_env env "prop_gen_fn composes inside df columns"
    "prop_for_all(prop_gen_df([w: prop_gen_fn(\\(n) 7)], nrows = 5, na_prob = 0.0), \\(df) nrow(df) == 5, n = 3)"
    "PASS";
  test_env env "prop_gen_fn spec is inspectable dict"
    "prop_gen_fn(\\(n) n)"
    "{`gen`: \"fn\", `fn`: \\(n) -> <function>}";
  test_env env "prop_gen_fn arity error"
    "prop_gen_fn()"
    "expects 1 arguments but received 0";

  (* prop_stats — generator probe *)
  test_env env "prop_stats counts runs and value types"
    "prop_stats(prop_gen_int_range(0, 100), n = 10)"
    "{`n_runs`: 10, `n_errors`: 0, `value_types`: {`Int`: 10}";
  test_env env "prop_stats counts draw errors"
    "prop_stats(prop_such_that(prop_gen_int_range(0, 0), \\(x) x == 1), n = 5)"
    "{`n_runs`: 0, `n_errors`: 5, `value_types`: {`Error`: 5}";
  test_env env "prop_stats records df row sizes"
    "prop_stats(prop_gen_df([x: prop_gen_int_range(0, 5)], nrows = 8), n = 6)"
    "value_types`: {`DataFrame`: 6}, `nested_sizes`: {`df`: [8, 8, 8, 8, 8, 8]}";
  test_env env "prop_stats records vector sizes"
    "prop_stats(prop_gen_vector(prop_gen_int_range(0, 10), 5), n = 10)"
    "nested_sizes`: {`vector`: [5, 5, 5, 5, 5, 5, 5, 5, 5, 5]}";
  test_env env "prop_stats unknown named arg errors"
    "prop_stats(prop_gen_int(), bogus = 1)"
    "received unknown named argument `bogus`";
  test_env env "prop_stats n must be positive"
    "prop_stats(prop_gen_int(), n = 0)"
    "expects `n` to be a positive Int";

  (* prop_gen_between — bounded int generator with in-domain shrinking *)
  test_env env "prop_for_all PASS between draws in-domain"
    "prop_for_all(prop_gen_between(100, 200), \\(x) x >= 100 && x <= 200, n = 40)"
    "PASS";
  test_env env "prop_for_all PASS between single-value range"
    "set_seed(3)\nprop_for_all(prop_gen_between(7, 7), \\(x) x == 7, n = 20)"
    "PASS";
  test_env env "prop_for_all PASS between shrinks toward min"
    "set_seed(42)\nprop_for_all(prop_gen_between(100, 200), \\(x) x <= 100, n = 20)"
    "(shrunk): 101";
  test_env env "prop_for_all PASS between df column shrinks to min"
    "set_seed(3)\nprop_for_all(prop_gen_df([x: prop_gen_between(100, 200)], nrows = 30, na_prob = 0.0), \\(df) nrow(df) < 30, n = 1)"
    "<Int> 100, 100, 100, 100, 100, 100, 100, 100";
  test_env env "prop_for_all PASS between df column draws in-domain"
    "prop_for_all(prop_gen_df([x: prop_gen_between(100, 200)], nrows = 20, na_prob = 0.0), \\(df) nrow(df |> filter($x >= 100 && $x <= 200)) == nrow(df), n = 10)"
    "PASS";
  test_env env "prop_for_all between df column NA type is NA(Int)"
    "set_seed(7)\nprop_for_all(prop_gen_df([x: prop_gen_between(100, 200)], nrows = 30, na_prob = 1.0), \\(df) false, n = 1)"
    "<NA> NA(Int), NA(Int)";
  test_env env "prop_for_all all-NA between df shrinks to 0 rows"
    "set_seed(7)\nprop_for_all(prop_gen_df([x: prop_gen_between(100, 200)], nrows = 30, na_prob = 1.0), \\(df) false, n = 1)"
    "DataFrame(0 rows x 1 cols)";
  test_env env "prop_gen_between fast-path batch is reproducible"
    "set_seed(42)\na = prop_for_all(prop_gen_df([x: prop_gen_between(100, 200)], nrows = 20, na_prob = 0.1), \\(df) false, n = 3)\nset_seed(42)\nb = prop_for_all(prop_gen_df([x: prop_gen_between(100, 200)], nrows = 20, na_prob = 0.1), \\(df) false, n = 3)\na == b"
    "true";
  test_env env "prop_gen_between spec is inspectable dict"
    "prop_gen_between(100, 200)"
    "{`gen`: \"between\", `min`: 100, `max`: 200}";
  test_env env "prop_gen_between inverted bounds errors"
    "prop_gen_between(5, 1)"
    "requires max >= min, got [5, 1]";
  test_env env "prop_gen_between non-int bounds errors"
    "prop_gen_between(\"a\", 1)"
    "expects Int bounds, got String";
  test_env env "prop_gen_between arity error"
    "prop_gen_between()"
    "expects 2 arguments but received 0";
  test_env env "prop_gen_between nested in list shrinks toward lower bound"
    "set_seed(42)\nprop_for_all(prop_gen_list(prop_gen_between(100, 200), 5), \\(xs) false, n = 1)"
    "(shrunk): [100]";
  test_env env "prop_gen_between nested in vector shrinks toward lower bound"
    "set_seed(42)\nprop_for_all(prop_gen_vector(prop_gen_between(100, 200), 5), \\(xs) false, n = 1)"
    "(shrunk): Vector[100]";
  test_env env "prop_gen_between nested in choice shrinks toward lower bound"
    "set_seed(42)\nprop_for_all(prop_gen_choice([prop_gen_between(100, 200), prop_gen_between(300, 400)]), \\(x) false, n = 1)"
    "(shrunk): 100";

  (* prop_gen_dict — Dict generator *)
  test_env env "prop_gen_dict spec is inspectable dict"
    "prop_gen_dict([x: prop_gen_int_range(0, 5)])"
    "{`gen`: \"dict\"";
  test_env env "prop_for_all PASS dict draws in-domain"
    "prop_for_all(prop_gen_dict([x: prop_gen_int_range(0, 100)], na_prob = 0.0), \\(d) d.x >= 0 && d.x <= 100, n = 40)"
    "PASS";
  test_env env "prop_for_all dict between column shrinks toward min"
    "set_seed(42)\nprop_for_all(prop_gen_dict([x: prop_gen_between(100, 200)], na_prob = 0.0), \\(d) d.x <= 100, n = 20)"
    "(shrunk): {`x`: 101}";
  test_env env "prop_for_all dict NA injection makes NA values"
    "set_seed(42)\nprop_for_all(prop_gen_dict([x: prop_gen_int_range(0, 100)], na_prob = 1.0), \\(d) false, n = 1)"
    "{`x`: NA(Int)}";
  test_env env "prop_show_spec renders dict"
    "prop_show_spec(prop_gen_dict([x: prop_gen_between(100, 200)], na_prob = 0.0))"
    "prop_gen_dict([x: prop_gen_between(100, 200)], na_prob = 0.)";
  test_env env "prop_gen_dict multiple columns round-trip"
    "prop_for_all(prop_gen_dict([x: prop_gen_int_range(0, 5), s: prop_gen_one_of([\"a\", \"b\"])], na_prob = 0.0), \\(d) d.x >= 0 && d.x <= 5 && (d.s == \"a\" || d.s == \"b\"), n = 20)"
    "PASS";
  test_env env "prop_gen_dict non-dict columns errors"
    "prop_gen_dict(1)"
    "expects `columns` to be a Dict";
  assert_roundtrip "prop_show_spec round-trip dict" "" "prop_gen_dict([x: prop_gen_between(100, 200), s: prop_gen_one_of([\"a\", \"b\"])], na_prob = 0.0)";

  (* prop_show_spec — generator introspection *)
  test_env env "prop_show_spec renders int_range"
    "prop_show_spec(prop_gen_int_range(0, 100))"
    "prop_gen_int_range(0, 100)";
  test_env env "prop_show_spec renders between"
    "prop_show_spec(prop_gen_between(100, 200))"
    "prop_gen_between(100, 200)";
  test_env env "prop_show_spec renders int with defaults"
    "prop_show_spec(prop_gen_int())"
    "prop_gen_int(min = -10, max = 10)";
  test_env env "prop_show_spec renders bool"
    "prop_show_spec(prop_gen_bool())"
    "prop_gen_bool()";
  test_env env "prop_show_spec renders one_of strings"
    "prop_show_spec(prop_gen_one_of([\"red\", \"green\"]))"
    "prop_gen_one_of([\\\"red\\\", \\\"green\\\"])";
  test_env env "prop_show_spec renders string_from chars as list"
    "prop_show_spec(prop_gen_string_from(\"ab\", 1, 3))"
    "prop_gen_string_from([\\\"a\\\", \\\"b\\\"], 1, 3)";
  test_env env "prop_show_spec renders factor"
    "prop_show_spec(prop_gen_factor([\"low\", \"high\"]))"
    "prop_gen_factor([\\\"low\\\", \\\"high\\\"])";
  test_env env "prop_show_spec renders choice"
    "prop_show_spec(prop_gen_choice([prop_gen_int_range(0, 5), prop_gen_bool()]))"
    "prop_gen_choice([prop_gen_int_range(0, 5), prop_gen_bool()])";
  test_env env "prop_show_spec renders frequency"
    "prop_show_spec(prop_gen_frequency([[5, prop_gen_int(min = -10, max = 10)], [1, prop_gen_bool()]]))"
    "prop_gen_frequency([[5, prop_gen_int(min = -10, max = 10)], [1, prop_gen_bool()]])";
  test_env env "prop_show_spec renders resize"
    "prop_show_spec(prop_resize(prop_gen_vector(prop_gen_int_range(0, 5), 3), 20))"
    "prop_resize(prop_gen_vector(prop_gen_int_range(0, 5), 3), 20)";
  test_env env "prop_show_spec renders date_range dates"
    "prop_show_spec(prop_gen_date_range(ymd(\"2020-01-01\"), ymd(\"2021-06-15\")))"
    "prop_gen_date_range(parse_date(\\\"2020-01-01\\\", \\\"%Y-%m-%d\\\"), parse_date(\\\"2021-06-15\\\", \\\"%Y-%m-%d\\\"))";
  test_env env "prop_show_spec renders ymd_range"
    "prop_show_spec(prop_gen_ymd(2000, 2024))"
    "prop_gen_ymd(2000, 2024)";
  test_env env "prop_show_spec renders datetime range with tz arg"
    "prop_show_spec(prop_gen_date_range(ymd_hms(\"2020-06-01 00:00:00\"), ymd_hms(\"2020-06-01 23:59:59\")))"
    "prop_gen_date_range(parse_datetime(\\\"2020-06-01 00:00:00.000000\\\", \\\"%Y-%m-%d %H:%M:%S\\\"), parse_datetime(\\\"2020-06-01 23:59:59.000000\\\", \\\"%Y-%m-%d %H:%M:%S\\\"))";
  test_env env "prop_show_spec renders df"
    "prop_show_spec(prop_gen_df([x: prop_gen_between(100, 200)], nrows = 5, na_prob = 0.0))"
    "prop_gen_df([x: prop_gen_between(100, 200)], nrows = 5, na_prob = 0.)";
  test_env env "prop_show_spec closure map errors"
    "prop_show_spec(prop_map_gen(prop_gen_int_range(0, 5), \\(v) v))"
    "cannot render a `map` generator spec: it captures a closure";
  test_env env "prop_show_spec non-spec value errors"
    "prop_show_spec(123)"
    "invalid generator spec (missing `gen` field)";
  test_env env "prop_show_spec non-dict errors"
    "prop_show_spec(\"nope\")"
    "cannot render the generator spec: invalid generator spec (missing `gen` field)";

  (* prop_show_spec round-trip — rendered source must rebuild an
     equivalent generator (identical seeded draw streams) *)
  assert_roundtrip "prop_show_spec round-trip int_range" "" "prop_gen_int_range(0, 100)";
  assert_roundtrip "prop_show_spec round-trip between" "" "prop_gen_between(100, 200)";
  assert_roundtrip "prop_show_spec round-trip one_of" "" "prop_gen_one_of([10, 20])";
  assert_roundtrip "prop_show_spec round-trip choice" ""
    "prop_gen_choice([prop_gen_int_range(0, 5), prop_gen_bool()])";
  assert_roundtrip "prop_show_spec round-trip string_from" "" "prop_gen_string_from(\"ab\", 1, 3)";
  assert_roundtrip "prop_show_spec round-trip resize" ""
    "prop_resize(prop_gen_vector(prop_gen_int_range(0, 5), 3), 20)";
  assert_roundtrip "prop_show_spec round-trip date_range" ""
    "prop_gen_date_range(ymd(\"2020-01-01\"), ymd(\"2021-06-15\"))";
  assert_roundtrip "prop_show_spec round-trip ymd_range" ""
    "prop_gen_ymd(2000, 2024)";
  assert_roundtrip "prop_show_spec round-trip df with between column" ""
    "prop_gen_df([x: prop_gen_between(100, 200), b: prop_gen_bool()], nrows = 5, na_prob = 0.1)";

  (* prop_named / prop_test — named properties *)
  test_env env "prop_named returns inspectable dict"
    "prop_named(\"bounded\", \\(x) x <= 100)"
    "{`name`: \"bounded\", `property`: \\(x) -> <function>}";
  test_env env "prop_test PASS via macro"
    "set_seed(42)\nprop_test(prop_named(\"nonneg\", \\(x) x >= 0), prop_gen_between(0, 200))"
    "PASS";
  test_env env "prop_test failure report includes macro name"
    "set_seed(42)\nprop_test(prop_named(\"monotone\", \\(x) x <= 100), prop_gen_between(100, 200))"
    "STOP(Property monotone failed after";
  test_env env "prop_test failure shrinks toward min"
    "set_seed(42)\nprop_test(prop_named(\"monotone\", \\(x) x <= 100), prop_gen_between(100, 200))"
    "(shrunk): 101";
  test_env env "prop_test accepts n and shrink_verify named args"
    "set_seed(42)\nprop_test(prop_named(\"nonneg\", \\(x) x >= 0), prop_gen_between(0, 200), n = 20, shrink_verify = true)"
    "PASS";
  test_env env "prop_test accepts max_counterexamples"
    "set_seed(42)\nprop_test(prop_named(\"small\", \\(x) x < 150), prop_gen_between(0, 200), n = 20, max_counterexamples = 2)"
    "STOP(Property small failed after 4 of 20 runs (showing 2 counterexamples)";
  test_env env "prop_test unknown named arg errors"
    "set_seed(42)\nprop_test(prop_named(\"nonneg\", \\(x) x >= 0), prop_gen_between(0, 200), bogus = 1)"
    "received unknown named argument `bogus`";
  test_env env "prop_test non-macro first arg errors"
    "prop_test(42, prop_gen_int())"
    "Function `prop_test` expects a named property Dict, got Int";
  test_env env "prop_test macro missing property errors"
    "prop_test([name: \"x\"], prop_gen_int())"
    "expects a named property to have a `property` field";
  test_env env "prop_named accepts non-callable property (defers to eval_call)"
    "prop_named(\"x\", 42)"
    "{`name`: \"x\", `property`: 42}";
  test_env env "prop_test non-callable macro property errors at invocation"
    "set_seed(1)\nprop_test(prop_named(\"x\", 42), prop_gen_int(), n = 3)"
    "predicate: raised: Value of type Int is not callable";
  test_env env "prop_named non-string name errors"
    "prop_named(1, \\(x) true)"
    "expects `name` to be a String, got Int";
  test_env env "prop_named arity error"
    "prop_named(\"x\")"
    "expects 2 arguments but received 1";

  (* shrink_verify — opt-in exhaustive candidate verification *)
  test_env env "prop_for_all shrink_verify flag accepted"
    "set_seed(42)\nprop_for_all(prop_gen_between(0, 200), \\(x) x >= 0, n = 20, shrink_verify = true)"
    "PASS";
  test_env env "prop_for_all shrink_verify non-bool errors"
    "prop_for_all(prop_gen_between(0, 200), \\(x) x >= 0, n = 20, shrink_verify = 1)"
    "Flag `shrink_verify` must be Bool, but received Int";
  test_env env "prop_test shrink_verify non-bool errors"
    "set_seed(42)\nprop_test(prop_named(\"nonneg\", \\(x) x >= 0), prop_gen_between(0, 200), shrink_verify = \"yes\")"
    "Flag `shrink_verify` must be Bool, but received String";
  let blocker_dict =
    "d = [k1: 100, k2: 100, k3: 100, k4: 100, k5: 100, k6: 100, k7: 100, k8: 100, k9: 100, k10: 100, \
     k11: 100, k12: 100, k13: 100, k14: 100, k15: 100, k16: 100, k17: 100, k18: 100, k19: 100, k20: 100, \
     k21: 100, k22: 100, k23: 100, k24: 100, k25: 100, k26: 100, k27: 100, k28: 100, k29: 100, k30: 100, \
     k31: 100, k32: 100, k33: 100, k34: 100, k35: 100, k36: 100, k37: 100, k38: 100, k39: 100, k40: 100]\n"
  in
  let blocker_pred =
    "\\(d) !((d.k1 == 100 && d.k2 == 100 && d.k3 == 100 && d.k4 == 100 && d.k5 == 100 && d.k6 == 100 && d.k7 == 100 && d.k8 == 100 \
    && d.k9 == 100 && d.k10 == 100 && d.k11 == 100 && d.k12 == 100 && d.k13 == 100 && d.k14 == 100 && d.k15 == 100 && d.k16 == 100) \
    && (d.k40 == 100 || d.k40 == 50))"
  in
  let blocker_prog verify =
    Printf.sprintf "set_seed(1)\n%s%s\nprop_for_all(prop_gen_one_of([d]), %s, n = 1%s)"
      blocker_dict blocker_pred blocker_pred
      (if verify then ", shrink_verify = true" else "")
  in
  test_env env "shrink_verify=false stops at capped non-minimal counterexample"
    (blocker_prog false)
    "(shrunk): {`k1`: 100, `k2`: 100, `k3`: 100, `k4`: 100, `k5`: 100, `k6`: 100, `k7`: 100, `k8`: 100, `k9`: 100, `k10`: 100, `k11`: 100, `k12`: 100, `k13`: 100, `k14`: 100, `k15`: 100, `k16`: 100, `k17`: 100";
  test_env env "shrink_verify=true reaches minimal counterexample"
    (blocker_prog true)
    "`k40`: 50";

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
