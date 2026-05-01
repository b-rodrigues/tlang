let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Logical:\n";
  test "and true" "true && true" "true";
  test "and false" "true && false" "false";
  test "or true" "false || true" "true";
  test "not true" "!true" "false";
  test "not false" "!false" "true";

  Printf.printf "Short-circuit:\n";
  (* 1/0 is DivisionByZero. If short-circuit works, this is not evaluated. *)
  test "sc false && error" "false && (1/0)" "false";
  test "sc true || error" "true || (1/0)" "true";

  Printf.printf "Bitwise/Strict:\n";
  test "true & false" "true & false" "false";
  test "true | false" "true | false" "true";
  
  Printf.printf "Broadcasting:\n";
  test "vec .+ scalar" "[1, 2] .+ 1" "[2, 3]";
  test "vec .* vec" "[2, 3] .* [4, 5]" "[8, 15]";
  test "vec .== vec" "[1, 2] .== [1, 3]" "[true, false]";
  test "vec .& vec" "[true, false] .& [true, true]" "[true, false]";
  
  Printf.printf "Broadcasting with NA:\n";
  (* NA does not propagate implicitly, so 1 .+ NA results in Error *)
  test "vec .+ NA" "[1, 2] .+ NA" "[Error(NAPredicateError: \"Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.\"), Error(NAPredicateError: \"Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.\")]";

  Printf.printf "Deep Equality:\n";
  test "identical ints" "identical(1, 1)" "true";
  test "identical string/int" "identical(1, \"1\")" "false";
  test "identical nested lists" "identical([1, [2, 3]], [1, [2, 3]])" "true";
  test "identical lists different order" "identical([1, 2], [2, 1])" "false";
  test "identical dicts different order" "identical([a: 1, b: 2], [b: 2, a: 1])" "true";
  test "identical NAs" "identical(NA, NA)" "true";
  test "identical vectors" "identical([1, 2], [1, 2])" "true";
  test "identical mixed collections" "identical([1, [a: 2]], [1, [a: 2]])" "true";

  print_newline ()

