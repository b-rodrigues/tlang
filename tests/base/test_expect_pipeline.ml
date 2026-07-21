open Ast

let make_node_result () =
  VNodeResult {
    v = VInt 42;
    node_name = "test_node";
    diagnostics = Ast.Utils.empty_node_diagnostics;
  }

let run_tests pass_count fail_count failures eval_string _eval_string_env _test =
  Printf.printf "Testcraft — pipeline expectations:\n";
  let env = Packages.init_env () in
  let call name args = match Env.find_opt name env with
    | Some (VBuiltin { b_func; _ }) -> b_func args (ref env)
    | _ -> VError { code = NameError; message = "not found"; context = []; location = None; na_count = 0 }
  in
  let assert_result name result_str expected =
    let match_found =
      if result_str = expected then true
      else try
        let _ = Str.search_forward (Str.regexp expected) result_str 0 in
        true
      with Not_found | Failure _ -> false
    in
    if match_found then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  ✗ %s\n    Expected (regex): %s\n    Got:               %s\n" name expected result_str in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in
  let assert_pass name result =
    assert_result name (Ast.Utils.value_to_string result) "PASS"
  in
  let assert_stop name result =
    assert_result name (Ast.Utils.value_to_string result) "STOP("
  in
  let assert_hold name result =
    assert_result name (Ast.Utils.value_to_string result) "HOLD("
  in
  let assert_error name result =
    assert_result name (Ast.Utils.value_to_string result) "Error("
  in

  (* Setup test pipelines *)
  let p_simple = eval_string "pipeline { a = 1; b = a + 1 }" in
  let p_run = eval_string "pipeline { a = node(command = <{ 1 }>, runtime = Python); b = node(command = <{ 1 }>, runtime = R); c = node(command = <{ 1 }>) }" in
  let p_ser = eval_string "pipeline { a = node(command = <{ 1 }>, serializer = ^csv); b = node(command = <{ 1 }>, deserializer = ^json); c = node(command = <{ 1 }>, noop = true); d = node(command = <{ 1 }>) }" in
  let p_pat = eval_string "pipeline { some_node = 1; a = node(command = <{ 1 }>, pattern = map_pattern(some_node)) }" in

  (* 1. expect_pipeline *)
  assert_pass "expect_pipeline: valid pipeline"
    (call "expect_pipeline" [(None, p_simple)]);
  assert_stop "expect_pipeline: not a pipeline"
    (call "expect_pipeline" [(None, VInt 123)]);
  assert_hold "expect_pipeline: NA"
    (call "expect_pipeline" [(None, VNA NAGeneric)]);

  (* 2. expect_nodes *)
  assert_pass "expect_nodes: exact match"
    (call "expect_nodes" [(None, p_simple); (None, VList [(None, VString "a"); (None, VString "b")])]);
  assert_stop "expect_nodes: mismatch"
    (call "expect_nodes" [(None, p_simple); (None, VList [(None, VString "a")])]);
  assert_error "expect_nodes: wrong arg type"
    (call "expect_nodes" [(None, p_simple); (None, VInt 123)]);

  (* 3. expect_dependency *)
  assert_pass "expect_dependency: simple dependency"
    (call "expect_dependency" [(None, p_simple); (None, VString "a"); (None, VString "b")]);
  assert_stop "expect_dependency: reverse direction"
    (call "expect_dependency" [(None, p_simple); (None, VString "b"); (None, VString "a")]);
  assert_stop "expect_dependency: from node nonexistent"
    (call "expect_dependency" [(None, p_simple); (None, VString "nonexistent"); (None, VString "b")]);
  assert_stop "expect_dependency: to node nonexistent"
    (call "expect_dependency" [(None, p_simple); (None, VString "a"); (None, VString "nonexistent")]);

  (* 4. expect_has_pattern *)
  assert_pass "expect_has_pattern: has map pattern"
    (call "expect_has_pattern" [(None, p_pat); (None, VString "a")]);
  assert_stop "expect_has_pattern: no pattern"
    (call "expect_has_pattern" [(None, p_simple); (None, VString "a")]);

  (* 5. expect_runtime *)
  assert_pass "expect_runtime: Python"
    (call "expect_runtime" [(None, p_run); (None, VString "a"); (None, VString "Python")]);
  assert_pass "expect_runtime: R"
    (call "expect_runtime" [(None, p_run); (None, VString "b"); (None, VString "R")]);
  assert_pass "expect_runtime: default T"
    (call "expect_runtime" [(None, p_run); (None, VString "c"); (None, VString "T")]);
  assert_stop "expect_runtime: mismatch"
    (call "expect_runtime" [(None, p_run); (None, VString "a"); (None, VString "R")]);

  (* 6. expect_serializer *)
  assert_pass "expect_serializer: csv symbol"
    (call "expect_serializer" [(None, p_ser); (None, VString "a"); (None, VSymbol "csv")]);
  assert_pass "expect_serializer: csv string"
    (call "expect_serializer" [(None, p_ser); (None, VString "a"); (None, VString "csv")]);
  assert_pass "expect_serializer: default serializer"
    (call "expect_serializer" [(None, p_ser); (None, VString "d"); (None, VSymbol "default")]);
  assert_stop "expect_serializer: mismatch"
    (call "expect_serializer" [(None, p_ser); (None, VString "a"); (None, VSymbol "json")]);

  (* 7. expect_deserializer *)
  assert_pass "expect_deserializer: json symbol"
    (call "expect_deserializer" [(None, p_ser); (None, VString "b"); (None, VSymbol "json")]);
  assert_pass "expect_deserializer: json string"
    (call "expect_deserializer" [(None, p_ser); (None, VString "b"); (None, VString "json")]);
  assert_pass "expect_deserializer: default deserializer"
    (call "expect_deserializer" [(None, p_ser); (None, VString "d"); (None, VSymbol "default")]);
  assert_stop "expect_deserializer: mismatch"
    (call "expect_deserializer" [(None, p_ser); (None, VString "b"); (None, VSymbol "csv")]);

  (* 8. expect_noop *)
  assert_pass "expect_noop: true"
    (call "expect_noop" [(None, p_ser); (None, VString "c"); (None, VBool true)]);
  assert_pass "expect_noop: false"
    (call "expect_noop" [(None, p_ser); (None, VString "a"); (None, VBool false)]);
  assert_stop "expect_noop: mismatch"
    (call "expect_noop" [(None, p_ser); (None, VString "c"); (None, VBool false)]);

  (* 9. expect_computed *)
  let node_res = make_node_result () in
  assert_pass "expect_computed: computed node result"
    (call "expect_computed" [(None, node_res)]);
  assert_stop "expect_computed: uncomputed node"
    (call "expect_computed" [(None, VNA NAGeneric)]);

  Printf.printf "\n"
