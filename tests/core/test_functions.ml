let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Functions:\n";
  test "lambda definition and call" "f = \\(x) x + 1; f(5)" "6";
  test "function keyword" "f = function(x) x * 2; f(3)" "6";
  test "two-arg function" "add = \\(a, b) a + b; add(3, 4)" "7";
  test "closure" "make_adder = \\(n) \\(x) x + n; add5 = make_adder(5); add5(10)" "15";
  test "autoquoted parameter binds bare name as symbol" "f = \\($col) col; f(age)" "age";
  test "autoquoted parameter also accepts column-ref call syntax" "f = \\($col) col; f($age)" "age";
  test "autoquoted parameter works with select" "f = \\(df, $col) select(df, col); df = dataframe([age: [1, 2], wt: [3, 4]]); colnames(f(df, age))" "[\"age\"]";
  test "autoquoted parameter works with summarize unquote"
    "f = \\(df, $col) summarize(df, result = mean(!!col)); df = dataframe([age: [1, 2], wt: [3, 4]]); get(pull(f(df, age), \"result\"), 0)"
    "1.5";
  test "autoquoted parameter keeps working when caller passes $column"
    "f = \\(df, $col) summarize(df, result = mean(!!col)); df = dataframe([age: [1, 2], wt: [3, 4]]); get(pull(f(df, $age), \"result\"), 0)"
    "1.5";
  test "autoquoted parameter works with mutate unquote"
    "f = \\(df, $col) mutate(df, copy = !!col); df = dataframe([age: [1, 2], wt: [3, 4]]); get(pull(f(df, age), \"copy\"), 1)"
    "2";
  test "autoquoted parameter rejects complex expressions"
    "f = \\($col) col; f(1 + 2)"
    {|Error(TypeError: "Auto-quoted parameters expect a bare name, $column, String, or Symbol.")|};
  test "arity error" "f = \\(x) x; f(1, 2)" {|Error(ArityError: "Function expects 1 arguments but received 2.")|};
  print_newline ()
