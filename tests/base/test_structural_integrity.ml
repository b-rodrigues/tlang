let run_tests _pass_count _fail_count _eval_string eval_string_env test =
  let temp_dir = Filename.get_temp_dir_name () in
  (* Use an existing directory as a write target so file creation reliably fails. *)
  let invalid_write_path = temp_dir in
  (* Keep this directory absent so these reads reliably exercise missing-file branches. *)
  let nonexistent_dir =
    Filename.concat temp_dir
      (Printf.sprintf "tlang-base-missing-%d" (Unix.getpid ()))
  in
  let missing_tobj_path = Filename.concat nonexistent_dir "missing.tobj" in
  let missing_json_path = Filename.concat nonexistent_dir "missing.json" in
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

  test "length() on dataframe raises error (ambiguous)"
    {|df = dataframe([a: [1, 2, 3]]); length(df)|}
    {|Error(TypeError: "length does not work on DataFrames because it is ambiguous (rows vs columns). Use nrow() or ncol() instead.")|};
  
  test "length() on empty dataframe raises error"
    {|length(dataframe([a: []]))|}
    {|Error(TypeError: "length does not work on DataFrames because it is ambiguous (rows vs columns). Use nrow() or ncol() instead.")|};

  print_newline ();

  Printf.printf "Structural Integrity — Serialization Roundtrip:\n";

  test "StructuralError survived serialization"
    {|p = "test_ser.tobj"; serialize(error("StructuralError", "topology break"), p); v = deserialize(p); v|}
    {|Error(StructuralError: "topology break")|};
  test "serialize type mismatch"
    {|serialize(1, 2)|}
    {|Error(TypeError: "Function `serialize` expects (Any, String).")|};
  test "deserialize type mismatch"
    {|deserialize(1)|}
    {|Error(TypeError: "Function `deserialize` expects a String path.")|};
  test "serialize directory write surfaces FileError"
    (Printf.sprintf {|serialize(1, "%s")|} invalid_write_path)
    {|Error(FileError: "serialize failed:|};
  test "deserialize missing file surfaces FileError"
    (Printf.sprintf {|deserialize("%s")|} missing_tobj_path)
    {|Error(FileError: "deserialize failed:|};

  print_newline ();

  Printf.printf "Structural Integrity — JSON roundtrip and errors:\n";

  let json_path = Filename.concat temp_dir (Printf.sprintf "tlang-base-%d.json" (Unix.getpid ())) in
  test "JSON scalar roundtrip"
    (Printf.sprintf {|p = "%s"; t_write_json(42, p); t_read_json(p)|} json_path)
    "42";
  test "t_write_json type mismatch"
    {|t_write_json(1, 2)|}
    {|Error(TypeError: "Function `t_write_json` expects (Any, String).")|};
  test "t_read_json type mismatch"
    {|t_read_json(1)|}
    {|Error(TypeError: "Function `t_read_json` expects a String path.")|};
  test "t_write_json directory write surfaces FileError"
    (Printf.sprintf {|t_write_json(1, "%s")|} invalid_write_path)
    {|Error(FileError: "t_write_json failed:|};
  test "t_read_json missing file surfaces FileError"
    (Printf.sprintf {|t_read_json("%s")|} missing_json_path)
    {|Error(FileError: "t_read_json failed:|};
  (try Sys.remove json_path with _ -> ());

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
