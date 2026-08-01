open Ast

let make_warning_node ?(kind = "NAExcluded") ?(message = "filter() excluded 1 row") () =
  VNodeResult {
    v = VInt 42;
    node_name = "test";
    diagnostics = {
      nd_warnings = [{
        nw_kind = kind;
        nw_fn = "filter";
        nw_na_count = 1;
        nw_na_indices = [0];
        nw_message = message;
        nw_source = WarningOwn;
      }];
      nd_error = None;
      nd_warnings_suppressed = false;
      nd_recovered = false;
      nd_upstream_errors = [];
    };
  }

let make_node_without_warnings () =
  VNodeResult {
    v = VInt 42;
    node_name = "test";
    diagnostics = Ast.Utils.empty_node_diagnostics;
  }

let run_tests pass_count fail_count failures _eval_string eval_string_env test =
  Printf.printf "Testcraft — condition:\n";
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
  let assert_stop name ?contains result =
    let result_str = Ast.Utils.value_to_string result in
    match contains with
    | Some pat ->
        let inner = match result with
          | VExpect (Expect_stop msg) -> msg
          | _ -> ""
        in
        let ok = try ignore (Str.search_forward (Str.regexp pat) inner 0); true
                 with Not_found | Failure _ -> false
        in
        if ok then begin
          incr pass_count;
          Printf.printf "  ✓ %s\n" name
        end else begin
          incr fail_count;
          let msg = Printf.sprintf "  ✗ %s\n    Expected STOP containing: %s\n    Got: %s\n" name pat result_str in
          failures := msg :: !failures;
          Printf.printf "%s" msg
        end
    | None -> assert_result name result_str "STOP("
  in
  let assert_hold name result =
    assert_result name (Ast.Utils.value_to_string result) "HOLD("
  in
  let assert_error name ?contains result =
    let result_str = Ast.Utils.value_to_string result in
    match contains with
    | Some pat ->
        let inner = match result with
          | VError err -> err.message
          | VExpect (Expect_stop msg) -> msg
          | _ -> ""
        in
        let ok = try ignore (Str.search_forward (Str.regexp pat) inner 0); true
                 with Not_found | Failure _ -> false
        in
        if ok then begin
          incr pass_count;
          Printf.printf "  ✓ %s\n" name
        end else begin
          incr fail_count;
          let msg = Printf.sprintf "  ✗ %s\n    Expected VError containing: %s\n    Got: %s\n" name pat result_str in
          failures := msg :: !failures;
          Printf.printf "%s" msg
        end
    | None -> assert_result name result_str "Error("
  in

  (* T-level tests through the evaluator (validates ~unwrap:false integration) *)
  test "expect_warning NA holds" "expect_warning(NA)" "HOLD(";
  test "expect_warning Error stops" "expect_warning(error(\"boom\"))" "STOP(`node` is an error: boom";
  test "expect_warning wrong type" "expect_warning(123)" "Error(TypeError:";

  (* Integration test: ~unwrap:false via evaluator with custom helper *)
  let integration_env = Env.add "make_test_warning_node"
    (Ast.make_builtin ~name:"make_test_warning_node" ~unwrap:false 0
       (fun _ _ -> make_warning_node ()))
    (Packages.init_env ())
  in
  let integ_result = fst (eval_string_env
    "expect_warning(make_test_warning_node())" integration_env) in
  assert_pass "expect_warning via evaluator" integ_result;

  (* Basic pass: node with a warning *)
  assert_pass "expect_warning pass"
    (call "expect_warning" [(None, make_warning_node ())]);

  (* Stop: node with no warnings *)
  assert_stop "expect_warning no warnings"
    (call "expect_warning" [(None, make_node_without_warnings ())]);

  (* Kind matching *)
  assert_pass "expect_warning kind match"
    (call "expect_warning" [(Some "kind", VString "NAExcluded"); (None, make_warning_node ())]);

  assert_stop "expect_warning kind mismatch"
    (call "expect_warning" [(Some "kind", VString "WrongKind"); (None, make_warning_node ())]);

  (* Message regex matching *)
  assert_pass "expect_warning message match"
    (call "expect_warning" [(Some "message", VString "excluded"); (None, make_warning_node ())]);

  assert_stop "expect_warning message no match"
    (call "expect_warning" [(Some "message", VString "nonexistent"); (None, make_warning_node ())]);

  (* Kind + message combined *)
  assert_pass "expect_warning kind+message match"
    (call "expect_warning"
       [(Some "kind", VString "NAExcluded");
        (Some "message", VString "excluded");
        (None, make_warning_node ())]);

  assert_stop "expect_warning kind+message mismatch"
    (call "expect_warning"
       [(Some "kind", VString "NAExcluded");
        (Some "message", VString "nonexistent");
        (None, make_warning_node ())]);

  (* NA handling *)
  assert_hold "expect_warning NA"
    (call "expect_warning" [(None, VNA NAGeneric)]);

  (* Error handling *)
  assert_stop "expect_warning Error" ~contains:"error"
    (call "expect_warning" [(None, Error.make_error GenericError "boom")]);

  (* Multiple warnings: should match any *)
  let multi_warn_node = VNodeResult {
    v = VInt 42;
    node_name = "multi";
    diagnostics = {
      nd_warnings = [
        { nw_kind = "KindA"; nw_fn = "fn1"; nw_na_count = 0; nw_na_indices = [];
          nw_message = "first warning"; nw_source = WarningOwn };
        { nw_kind = "KindB"; nw_fn = "fn2"; nw_na_count = 1; nw_na_indices = [0];
          nw_message = "second warning"; nw_source = WarningOwn };
      ];
      nd_error = None;
      nd_warnings_suppressed = false;
      nd_recovered = false;
      nd_upstream_errors = [];
    };
  } in
  assert_pass "expect_warning multi match kindA"
    (call "expect_warning" [(Some "kind", VString "KindA"); (None, multi_warn_node)]);
  assert_pass "expect_warning multi match kindB"
    (call "expect_warning" [(Some "kind", VString "KindB"); (None, multi_warn_node)]);
  assert_pass "expect_warning multi match message"
    (call "expect_warning" [(Some "message", VString "second"); (None, multi_warn_node)]);
  assert_stop "expect_warning multi no match"
    (call "expect_warning" [(Some "kind", VString "KindC"); (None, multi_warn_node)]);

  (* Upstream warnings *)
  let upstream_warn_node = VNodeResult {
    v = VInt 42;
    node_name = "upstream";
    diagnostics = {
      nd_warnings = [{
        nw_kind = "NAExcluded";
        nw_fn = "filter";
        nw_na_count = 1;
        nw_na_indices = [0];
        nw_message = "filter() excluded 1 row";
        nw_source = WarningUpstream "ancestor_node";
      }];
      nd_error = None;
      nd_warnings_suppressed = false;
      nd_recovered = false;
      nd_upstream_errors = [];
    };
  } in
  assert_pass "expect_warning upstream"
    (call "expect_warning" [(None, upstream_warn_node)]);

  (* Empty string filters treated as omitted *)
  assert_pass "expect_warning empty kind works"
    (call "expect_warning" [(Some "kind", VString ""); (None, make_warning_node ())]);

  assert_pass "expect_warning empty message works"
    (call "expect_warning" [(Some "message", VString ""); (None, make_warning_node ())]);

  (* Computed node: resolved with warning *)
  let cn_record = {
    Ast.cn_name = "test_cn";
    cn_runtime = "T";
    cn_path = "";
    cn_serializer = "csv";
    cn_class = "";
    cn_dependencies = [];
    cn_p_exprs = None;
    cn_flake = None;
    cn_config = None;
  } in
  Ast.set_in_memory_node_value ~p_exprs:[] ~node_name:"test_cn" (make_warning_node ());
  assert_pass "expect_warning computed node resolved"
    (call "expect_warning" [(None, VComputedNode cn_record)]);

  (* Computed node: unresolved *)
  let unresolved_cn = { cn_record with cn_name = "unresolved_cn" } in
  assert_stop "expect_warning computed node unresolved" ~contains:"has not been evaluated"
    (call "expect_warning" [(None, VComputedNode unresolved_cn)]);

  (* Error cases *)
  assert_error "expect_warning invalid regex" ~contains:"Invalid regex pattern"
    (call "expect_warning" [(Some "message", VString "["); (None, make_warning_node ())]);

  assert_error "expect_warning unknown named arg"
    (call "expect_warning" [(Some "foo", VInt 1); (None, make_warning_node ())]);

  assert_error "expect_warning kind wrong type"
    (call "expect_warning" [(Some "kind", VInt 1); (None, make_warning_node ())]);

  assert_error "expect_warning message wrong type"
    (call "expect_warning" [(Some "message", VInt 1); (None, make_warning_node ())]);

  assert_error "expect_warning wrong positional type" ~contains:"expects a NodeResult"
    (call "expect_warning" [(None, VInt 123)]);

  Printf.printf "\n"
