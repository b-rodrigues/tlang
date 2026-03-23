let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Pipe Operator:\n";
  test "pipe to function" "double = \\(x) x * 2; 5 |> double" "10";
  test "pipe with args" "add = \\(a, b) a + b; 5 |> add(3)" "8";
  test "pipe chain" "double = \\(n) n * 2; inc = \\(m) m + 1; 5 |> double |> inc" "11";
  test "pipe to builtin" "42 |> type" {|"Int"|};
  test "pipe chain across lines"
    "[1, 2, 3]\n  |> map(\\(x) x * x)\n  |> sum"
    "14";
  test "pipe short-circuits on error"
    "double = \\(x) x * 2; error(\"boom\") |> double"
    {|Error(GenericError: "boom")|};
  print_newline ();

  Printf.printf "Maybe-Pipe Operator:\n";
  test "maybe-pipe forwards normal value"
    "double = \\(x) x * 2; 5 ?|> double"
    "10";
  test "maybe-pipe forwards error to function"
    "handle = \\(x) if (is_error(x)) \"recovered\" else x; error(\"boom\") ?|> handle"
    {|"recovered"|};
  test "maybe-pipe with args"
    "add = \\(a, b) a + b; 5 ?|> add(3)"
    "8";
  test "maybe-pipe chain"
    "double = \\(x) x * 2; inc = \\(x) x + 1; 5 ?|> double ?|> inc"
    "11";
  test "maybe-pipe to builtin"
    "42 ?|> type"
    {|"Int"|};
  test "maybe-pipe error to is_error"
    "error(\"test\") ?|> is_error"
    "true";
  test "mixed pipe chain: maybe-pipe then pipe"
    "recovery = \\(x) if (is_error(x)) 0 else x; inc = \\(x) x + 1; error(\"fail\") ?|> recovery |> inc"
    "1";
  test "maybe-pipe chain across lines"
    "double = \\(x) x * 2\ninc = \\(x) x + 1\n5\n  ?|> double\n  ?|> inc"
    "11";
  print_newline ()
