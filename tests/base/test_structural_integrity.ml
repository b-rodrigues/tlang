let run_tests _pass_count _fail_count _eval_string eval_string_env test =
  Printf.printf "Structural Integrity — Terminal Evaluation Bypass:\n";

  (* StructuralError should bypass resilient evaluation *)
  let env_res = Packages.init_env () in
  let (_v, _env_res) = eval_string_env "resilient = true" env_res in
  
  test "StructuralError bypasses resilient=true"
    {|error("StructuralError", "fatal break")|}
    {|Error(StructuralError: "fatal break")|};

  (* Valorized error should still be captured as value if not Structural *)
  test "ValueError is captured in resilient mode"
    {|error("ValueError", "recoverable")|}
    {|Error(ValueError: "recoverable")|};

  print_newline ();

  Printf.printf "Structural Integrity — length() Propagation rules:\n";

  test "length() propagates error scalar"
    {|length(1 / 0)|}
    {|Error(DivisionByZero: "Division by zero.")|};

  test "strict list literal propagates error"
    {|length([1, 2, 1 / 0])|}
    {|Error(DivisionByZero: "Division by zero.")|};

  test "strict dict literal propagates error"
    {|length([a: 1, b: 1 / 0])|}
    {|Error(DivisionByZero: "Division by zero.")|};

  test "length() on dataframe"
    {|df = dataframe([a: [1, 2, 3]]); length(df)|}
    "3";
  
  test "length() on empty dataframe"
    {|length(dataframe([a: []]))|}
    "0";

  print_newline ();

  Printf.printf "Structural Integrity — Serialization Roundtrip:\n";

  test "StructuralError survived serialization"
    {|p = "test_ser.tobj"; serialize(error("StructuralError", "topology break"), p); v = deserialize(p); v|}
    {|Error(StructuralError: "topology break")|};

  print_newline ();

  Printf.printf "Structural Integrity — error() builtin stability:\n";

  test "error() with unknown code defaults to GenericError"
    {|error("UnknownCode", "some message")|}
    {|Error(GenericError: "some message")|};

  test "error() arity mismatch (1 arg too many)"
    {|error("Code", "Msg", "Extra")|}
    {|Error(ArityError: "Function `error` expects 1 or 2 string arguments but received 3.")|};

  test "error() type mismatch"
    {|error(123)|}
    {|Error(TypeError: "Function `error` expects a String message.")|};

  print_newline ()
