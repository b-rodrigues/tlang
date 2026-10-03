let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env _test test_env =
  Printf.printf "Dicts:\n";
  let env = Packages.init_env () in
  test_env env "empty dict" "[:]" "{}";
  test_env env "dict literal" {|[x: 1, y: 2]|} {|{`x`: 1, `y`: 2}|};
  test_env env "dict dot access" "[x: 42, y: 99].x" "42";
  test_env env "dict missing key" "[x: 1].z" {|Error(KeyError: "Key `z` not found in Dict.")|};
  test_env env "nested dict intermediate" "[a: [b: 1]].a" "{`b`: 1}";
  test_env env "nested dict access" "[a: [b: 1]].a.b" "1";
  test_env env "nested missing key" "[a: [b: 1]].a.z" "Key `z` not found in Dict.";
  test_env env "dict length" "length([a: 1, b: 2])" "2";
  print_newline ()
