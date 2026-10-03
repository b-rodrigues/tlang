let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "Dicts:\n";
  test "empty dict" "[:]" "{}";
  test "dict literal" {|[x: 1, y: 2]|} {|{`x`: 1, `y`: 2}|};
  test "dict dot access" "[x: 42, y: 99].x" "42";
  test "dict missing key" "[x: 1].z" {|Error(KeyError: "Key `z` not found in Dict.")|};
  test "nested dict intermediate" "[a: [b: 1]].a" "{`b`: 1}";
  test "nested dict access" "[a: [b: 1]].a.b" "1";
  test "nested missing key" "[a: [b: 1]].a.z" "Key `z` not found in Dict.";
  test "dict length" "length([a: 1, b: 2])" "2";
  print_newline ()
