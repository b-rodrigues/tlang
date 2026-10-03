let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "Comparisons:\n";
  test "equality true" "1 == 1" "true";
  test "equality false" "1 == 2" "false";
  test "not equal" "1 != 2" "true";
  test "less than" "1 < 2" "true";
  test "less than false" "2 < 1" "false";
  test "greater than" "3 > 2" "true";
  test "greater than false" "1 > 2" "false";
  test "less or equal" "2 <= 2" "true";
  test "less or equal false" "3 <= 2" "false";
  test "greater or equal" "3 >= 3" "true";
  test "greater or equal false" "2 >= 3" "false";
  test "equality mixed int float" "1 == 1.0" "true";
  test "string equality true" {|"a" == "a"|} "true";
  test "string equality false" {|"a" == "b"|} "false";
  test "mixed type error" {|1 < "a"|} "expects Int and String";
  test "NA comparison is error" "NA == 1" "Operation on NA";
  test "date greater than" {|ymd("2024-01-02") > ymd("2024-01-01")|} "true";
  test "date less than" {|ymd("2024-01-01") < ymd("2024-01-02")|} "true";
  test "factor equality true" {|f = to_factor(["a", "b"]); get(f, 0) == get(f, 0)|} "true";
  test "factor equality false" {|f = to_factor(["a", "b"]); get(f, 0) == get(f, 1)|} "false";
  print_newline ()
