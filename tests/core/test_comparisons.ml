let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env _test test_env test_equal =
  Printf.printf "Comparisons:\n";
  let env = Packages.init_env () in
  test_equal env "equality true" "1 == 1" "true";
  test_equal env "equality false" "1 == 2" "false";
  test_equal env "not equal" "1 != 2" "true";
  test_equal env "less than" "1 < 2" "true";
  test_equal env "less than false" "2 < 1" "false";
  test_equal env "greater than" "3 > 2" "true";
  test_equal env "greater than false" "1 > 2" "false";
  test_equal env "less or equal" "2 <= 2" "true";
  test_equal env "less or equal false" "3 <= 2" "false";
  test_equal env "greater or equal" "3 >= 3" "true";
  test_equal env "greater or equal false" "2 >= 3" "false";
  test_equal env "equality mixed int float" "1 == 1.0" "true";
  test_equal env "string equality true" {|"a" == "a"|} "true";
  test_equal env "string equality false" {|"a" == "b"|} "false";
  test_env env "mixed type error" {|1 < "a"|} "expects Int and String";
  test_env env "NA comparison is error" "NA == 1" "Operation on NA";
  test_equal env "date greater than" {|ymd("2024-01-02") > ymd("2024-01-01")|} "true";
  test_equal env "date less than" {|ymd("2024-01-01") < ymd("2024-01-02")|} "true";
  test_equal env "factor equality true" {|f = to_factor(["a", "b"]); get(f, 0) == get(f, 0)|} "true";
  test_equal env "factor equality false" {|f = to_factor(["a", "b"]); get(f, 0) == get(f, 1)|} "false";
  test_env env "string ordering is error" {|"a" < "b"|} "expects String and String";
  test_equal env "date equality" {|ymd("2024-01-01") == ymd("2024-01-01")|} "true";
  test_env env "NA on the right is error" "1 == NA" "Operation on NA";
  test_env env "chained comparison raises raw parser exception (known issue: no clean diagnostic)"
    "1 < 2 < 3" {|EXCEPTION: Parser.MenhirBasics.Error|};
  print_newline ()
