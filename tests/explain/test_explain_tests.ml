let run_tests pass_count fail_count _eval_string eval_string_env test =
  Printf.printf "Phase 6 — Intent Blocks:\n";
  test "intent block creation"
    {|intent { description: "Load data", assumes: "File exists" }|}
    {|Intent{description: "Load data", assumes: "File exists"}|};
  test "intent type"
    {|type(intent { description: "test" })|}
    {|"Intent"|};
  test "intent block assignment"
    {|i = intent { goal: "compute mean" }; type(i)|}
    {|"Intent"|};
  test "intent block with expression values"
    {|x = "dynamic"; intent { note: x }|}
    {|Intent{note: "dynamic"}|};
  print_newline ();

  Printf.printf "Phase 6 — Intent Fields:\n";
  test "intent_fields returns Dict"
    {|i = intent { description: "test", version: "1.0" }; type(intent_fields(i))|}
    {|"Dict"|};
  test "intent_fields values"
    {|i = intent { a: "hello", b: "world" }; intent_fields(i)|}
    {|{`a`: "hello", `b`: "world"}|};
  test "intent_fields on non-intent"
    "intent_fields(42)"
    {|Error(TypeError: "Function `intent_fields` expects an Intent value.")|};
  print_newline ();

  Printf.printf "Phase 6 — Intent Get:\n";
  test "intent_get specific field"
    {|i = intent { description: "test", author: "T" }; intent_get(i, "description")|}
    {|"test"|};
  test "intent_get missing field"
    {|i = intent { a: "1" }; intent_get(i, "b")|}
    {|Error(KeyError: "Intent field `b` not found.")|};
  test "intent_get on non-intent"
    {|intent_get(42, "x")|}
    {|Error(TypeError: "Function `intent_get` expects an Intent value as first argument.")|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Scalars:\n";
  test "explain integer kind"
    {|e = explain(42); e.kind|}
    {|"value"|};
  test "explain integer type"
    {|e = explain(42); e.type|}
    {|"Int"|};
  test "explain string"
    {|e = explain("hello"); e.type|}
    {|"String"|};
  test "explain bool"
    {|e = explain(true); e.type|}
    {|"Bool"|};
  test "explain float"
    {|e = explain(3.14); e.type|}
    {|"Float"|};
  test "explain null"
    {|e = explain(null); e.type|}
    {|"Null"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: NA:\n";
  test "explain NA kind"
    {|e = explain(NA); e.kind|}
    {|"value"|};
  test "explain NA type"
    {|e = explain(NA); e.type|}
    {|"NA"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Vectors:\n";
  test "explain vector kind"
    {|v = [1, 2, 3]; e = explain(v); e.kind|}
    {|"value"|};
  test "explain vector type"
    {|v = [1, 2, 3]; e = explain(v); e.type|}
    {|"List"|};
  test "explain vector length"
    {|v = [1, 2, 3]; e = explain(v); e.length|}
    "3";
  test "explain vector na_count"
    {|v = [1, NA, 3]; e = explain(v); e.na_count|}
    "1";
  print_newline ();

  Printf.printf "Phase 6 — Explain: DataFrame:\n";
  (* Create test CSV for explain tests *)
  let csv_p6 = "test_phase6.csv" in
  let oc7 = open_out csv_p6 in
  output_string oc7 "name,age,score\nAlice,30,95.5\nBob,NA,87.3\nCharlie,35,NA\n";
  close_out oc7;

  let env_p6 = Eval.initial_env () in
  let (_, env_p6) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_p6) env_p6 in
  let (v, _) = eval_string_env "e = explain(df); e.kind" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = {|"dataframe"|} then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame kind\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame kind\n    Expected: \"dataframe\"\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(df); e.nrow" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame nrow\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame nrow\n    Expected: 3\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(df); e.ncol" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame ncol\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame ncol\n    Expected: 3\n    Got: %s\n" result
  end;

  (* Check NA stats *)
  let (v, _) = eval_string_env "e = explain(df); e.na_stats.age" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = "1" then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame NA stats (age has 1 NA)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame NA stats (age has 1 NA)\n    Expected: 1\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(df); e.na_stats.score" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = "1" then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame NA stats (score has 1 NA)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame NA stats (score has 1 NA)\n    Expected: 1\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(df); e.na_stats.name" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = "0" then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame NA stats (name has 0 NAs)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame NA stats (name has 0 NAs)\n    Expected: 0\n    Got: %s\n" result
  end;

  (* Check schema *)
  let (v, _) = eval_string_env "e = explain(df); type(e.schema)" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = {|"List"|} then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame schema is a List\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame schema is a List\n    Expected: \"List\"\n    Got: %s\n" result
  end;

  (* Check example rows *)
  let (v, _) = eval_string_env "e = explain(df); type(e.example_rows)" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = {|"List"|} then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame example_rows is a List\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame example_rows is a List\n    Expected: \"List\"\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(df); length(e.example_rows)" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame example_rows length (3 rows)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame example_rows length (3 rows)\n    Expected: 3\n    Got: %s\n" result
  end;
  (try Sys.remove csv_p6 with _ -> ());
  print_newline ();

  Printf.printf "Phase 6 — Explain: Pipeline:\n";
  let (_, env_p6_pipe) = eval_string_env "p = pipeline {\n  x = 10\n  y = x + 5\n  z = y * 2\n}" (Eval.initial_env ()) in
  let (v, _) = eval_string_env "e = explain(p); e.kind" env_p6_pipe in
  let result = Ast.Utils.value_to_string v in
  if result = {|"pipeline"|} then begin
    incr pass_count; Printf.printf "  ✓ explain Pipeline kind\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain Pipeline kind\n    Expected: \"pipeline\"\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(p); e.node_count" env_p6_pipe in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ explain Pipeline node_count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain Pipeline node_count\n    Expected: 3\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 6 — Explain: Intent:\n";
  test "explain intent kind"
    {|i = intent { description: "test" }; e = explain(i); e.kind|}
    {|"intent"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Error:\n";
  test "explain error"
    {|e = explain(1 / 0); e.type|}
    {|"Error"|};
  test "explain error code"
    {|e = explain(1 / 0); e.error_code|}
    {|"DivisionByZero"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Arity:\n";
  test "explain no args"
    "explain()"
    {|Error(ArityError: "Function expects 1 arguments but received 0.")|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Pipeline Integration:\n";
  test "explain in pipe"
    {|42 |> explain|}
    {|{`kind`: "value", `type`: "Int", `value`: 42}|};
  print_newline ();

  Printf.printf "Phase 6 — Functions available without imports:\n";
  test "explain available" {|type(explain(42))|}  {|"Dict"|};
  test "intent_fields available" {|i = intent { a: "1" }; type(intent_fields(i))|} {|"Dict"|};
  test "intent_get available" {|i = intent { a: "1" }; intent_get(i, "a")|} {|"1"|};
  print_newline ()
