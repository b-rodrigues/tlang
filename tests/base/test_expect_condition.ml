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

let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env _test =
  Printf.printf "Testcraft — condition:\n";
  let env = Packages.init_env () in
  let call name args = match Env.find_opt name env with
    | Some (VBuiltin { b_func; _ }) -> b_func args (ref env)
    | _ -> VError { code = NameError; message = "not found"; context = []; location = None; na_count = 0 }
  in
  let assert_pass name result =
    match result with
    | VExpect Expect_pass ->
        Printf.printf "  ✓ %s\n" name
    | VExpect (Expect_stop msg) ->
        Printf.printf "  ✗ %s: STOP(%s)\n" name msg
    | VExpect (Expect_hold msg) ->
        Printf.printf "  ✗ %s: HOLD(%s)\n" name msg
    | other ->
        Printf.printf "  ✗ %s: unexpected %s\n" name (Utils.value_to_string other)
  in
  let assert_stop name ?contains result =
    match result with
    | VExpect (Expect_stop msg) ->
        let ok = match contains with
          | Some pat -> (try ignore (Str.search_forward (Str.regexp pat) msg 0); true
                         with Not_found -> false)
          | None -> true
        in
        if ok then Printf.printf "  ✓ %s\n" name
        else Printf.printf "  ✗ %s: STOP message did not contain expected pattern.\n    Got: %s\n" name msg
    | VExpect (Expect_hold msg) ->
        Printf.printf "  ✗ %s: expected STOP, got HOLD(%s)\n" name msg
    | other ->
        Printf.printf "  ✗ %s: expected STOP, got %s\n" name (Utils.value_to_string other)
  in
  let assert_hold name result =
    match result with
    | VExpect (Expect_hold _) ->
        Printf.printf "  ✓ %s\n" name
    | VExpect (Expect_stop msg) ->
        Printf.printf "  ✗ %s: expected HOLD, got STOP(%s)\n" name msg
    | other ->
        Printf.printf "  ✗ %s: expected HOLD, got %s\n" name (Utils.value_to_string other)
  in

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
  } in
  Ast.set_in_memory_node_value ~p_exprs:[] ~node_name:"test_cn" (make_warning_node ());
  assert_pass "expect_warning computed node resolved"
    (call "expect_warning" [(None, VComputedNode cn_record)]);

  (* Computed node: unresolved *)
  let unresolved_cn = { cn_record with cn_name = "unresolved_cn" } in
  assert_stop "expect_warning computed node unresolved" ~contains:"has not been evaluated"
    (call "expect_warning" [(None, VComputedNode unresolved_cn)]);

  (* Error cases *)
  let assert_error name ?contains result =
    match result with
    | VError err ->
        let ok = match contains with
          | Some pat -> (try ignore (Str.search_forward (Str.regexp pat) err.message 0); true
                         with Not_found -> false)
          | None -> true
        in
        if ok then Printf.printf "  ✓ %s\n" name
        else Printf.printf "  ✗ %s: VError message did not contain expected pattern.\n    Got: %s\n" name err.message
    | other ->
        Printf.printf "  ✗ %s: expected VError, got %s\n" name (Utils.value_to_string other)
  in

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
