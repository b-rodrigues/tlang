(* Regression tests for factor-grouping in count/summarize.
   Covers the arrow-native group-by root-cause fix in src/ffi/arrow_stubs.c:
   factor grouping keys must resolve to their level strings (not garbage
   dictionary indices), group order must follow level order (R-compatible),
   unused levels are dropped, and NA factor values form an NA group. *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Factor grouping — count/summarize on factor columns:\n";

  let env = Packages.init_env () in
  let env = Test_helpers.eval_setup eval_string_env env "test_factor_grouping:10" {|fdf = to_dataframe([g: to_factor(["a","a","a","b"])])|} in
  let env = Test_helpers.eval_setup eval_string_env env "test_factor_grouping:11" {|of = to_dataframe([g: to_factor(["b","a","c","a","b"], levels = ["c","b","a"])])|} in
  let env = Test_helpers.eval_setup eval_string_env env "test_factor_grouping:12" {|naf = to_dataframe([g: to_factor(["a", NA, "b", NA, "b"])])|} in
  let env = Test_helpers.eval_setup eval_string_env env "test_factor_grouping:13" {|un = to_dataframe([g: to_factor(["a","b","a"], levels = ["a","b","c","d"])])|} in
  let env = Test_helpers.eval_setup eval_string_env env "test_factor_grouping:14" {|sg = to_dataframe([g: to_factor(["a","a","b","b","b"]), x: [1,2,3,4,5]])|} in

  Printf.printf "  count() on factor columns:\n";
  test_env env "count on factor yields one row per used level"
    "nrow(count(fdf, $g))"
    "2";
  test_env env "count rows equal n_distinct of factor values"
    "nrow(count(fdf, $g)) == n_distinct(pull(fdf, \"g\"))"
    "true";
  test_env env "count n column sums to nrow"
    "sum(pull(count(fdf, $g), \"n\")) == nrow(fdf)"
    "true";
  test_env env "count groups follow level order not first-appearance order"
    "pull(count(of, $g), \"g\")"
    {|Vector[Factor("c"), Factor("b"), Factor("a")]|};
  test_env env "count result keeps factor levels intact"
    "levels(pull(count(of, $g), \"g\"))"
    {|Vector["c", "b", "a"]|};
  test_env env "NA factor value forms an NA group"
    "nrow(count(naf, $g))"
    "3";
  test_env env "count drops unused levels"
    "nrow(count(un, $g))"
    "2";
  print_newline ();

  Printf.printf "  summarize() grouped by factor:\n";
  test_env env "group_by+summarize on factor yields one row per level"
    "nrow(summarize(group_by(sg, $g), cnt = n()))"
    "2";
  test_env env "group sizes sum to nrow"
    "sum(pull(summarize(group_by(sg, $g), cnt = n()), \"cnt\")) == nrow(sg)"
    "true";
  print_newline ();
  print_newline ()
