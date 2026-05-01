let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Coverage Boost — Boolean & Control:\n";
  test "ifelse with out_type Int"
    {|ifelse([true, false], 1, 2, out_type = "Int")|}
    "Vector[1, 2]";
  test "ifelse with out_type Float"
    {|ifelse([true, false], 1, 2, out_type = "Float")|}
    "Vector[1., 2.]";
  test "ifelse with recycling true_val"
    {|ifelse([true, false, true], 42, 0)|}
    "Vector[42, 0, 42]";
  test "ifelse with missing value"
    {|ifelse([true, NA, false], 1, 0, missing = 999)|}
    "Vector[1, 999, 0]";
  test "case_when recycling"
    {|x = [1, 2, 3, 4]; casewhen(x .< 2 ~ "small", x .< 4 ~ "medium", .default = "large")|}
    {|Vector["small", "medium", "medium", "large"]|};
  test "case_when no match returns NA"
    {|x = [1, 5]; casewhen(x .< 2 ~ "small")|}
    {|Vector["small", NA]|};
  print_newline ();

  Printf.printf "Coverage Boost — Get & Lenses:\n";
  test "get from list by index" "get([10, 20, 30], 1)" "20";
  test "get from vector by index"
    {|df = dataframe([a: [10, 20]]); v = pull(df, "a"); get(v, 0)|}
    "10";
  test "get from dataframe by row lens"
    {|df = dataframe([mpg: [21, 22], cyl: [6, 6]]); get(df, row_lens(0)).mpg|}
    "21";
  test "get from dataframe by col lens"
    {|df = dataframe([mpg: [21, 22]]); get(df, col_lens("mpg")) |> head(n=1)|}
    "Vector[21]";
  test "compose lens"
    {|l = compose(row_lens(0), col_lens("mpg")); df = dataframe([mpg: [21, 22]]); get(df, l)|}
    "21";
  test "filter_lens on list"
    {|get([1, 10, 2, 20], filter_lens(\(x) x > 5))|}
    "[10, 20]";
  test "filter_lens on vector"
    {|df = dataframe([a: [1, 10, 2, 20]]); v = pull(df, "a"); get(v, filter_lens(\(x) x > 5))|}
    "Vector[10, 20]";
  test "filter_lens on dataframe"
    {|df = dataframe([mpg: [31, 21, 32, 22, 33, 23, 34, 24]]); get(df, filter_lens(\(r) r.mpg > 30)) |> nrow()|}
    "4";
  print_newline ();

  Printf.printf "Coverage Boost — Pretty Print:\n";
  (* We test that they don't crash and return NA (as they print to stdout) *)
  test "pretty_print int" "pretty_print(42)" "NA";
  test "pretty_print list" "pretty_print([1, 2, 3])" "NA";
  test "pretty_print nested dict" "pretty_print([a: [b: 1]])" "NA";
  test "pretty_print dataframe" {|df = dataframe([a: [1, 2], b: [3, 4]]); pretty_print(df)|} "NA";
  test "pretty_print summary"
    {|df = dataframe([a: [1, 2]]); s = [class: "summary", model_class: "lm", _tidy_df: df]; pretty_print(s)|}
    "NA";
  test "pretty_print visual metadata"
    {|v = [class: "altair", data: "json", _display_keys: ["class"]]; pretty_print(v)|}
    "NA";
  test "pretty_print tree"
    {|t = [kind: "node", name: "root", children: [1, 2], _display_keys: ["kind", "name", "children"]]; pretty_print(t)|}
    "NA";
  test "pretty_print pipeline" {|p = pipeline { a = 1 }; pretty_print(p)|} "NA";
  print_newline ();

  Printf.printf "Coverage Boost — Aggregation & Printing:\n";
  test "sum on vector" {|df = dataframe([a: [1, 2, 3]]); v = pull(df, "a"); sum(v)|} "6";
  test "sum on vector with NA" {|df = dataframe([a: [1, NA, 3]]); v = pull(df, "a"); sum(v, na_rm=true)|} "4";
  test "print silent returns NA" "print(42, silent=true)" "NA";
  test "print returns NA" "print(42)" "NA";
  print_newline ();

  Printf.printf "Coverage Boost — Converters:\n";
  test "to_integer on list" "to_integer([\"1\", \"2.5\"])" "[1, 2]";
  test "to_float on vector" {|df = dataframe([a: ["1.1", "2.2"]]); v = pull(df, "a"); to_float(v)|} "Vector[1.1, 2.2]";
  test "to_numeric on list" "to_numeric([1, \"2.2\"])" "[1., 2.2]";
