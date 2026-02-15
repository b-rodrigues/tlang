let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Dicts:\n";
  test "dict literal" {|[x: 1, y: 2]|} {|{`x`: 1, `y`: 2}|};
  test "dict dot access" "[x: 42, y: 99].x" "42";
  test "dict missing key" "[x: 1].z" {|Error(KeyError: "Key `z` not found in Dict.")|};
  print_newline ()
