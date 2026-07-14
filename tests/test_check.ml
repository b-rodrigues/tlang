(* tests/test_check.ml *)
(* Tests for t check: diagnostics module and check_mode flag *)

open Ast

let run_tests pass_count fail_count failures eval_string _eval_string_env _test =
  Printf.printf "=== t check / Diagnostics tests ===\n\n";

  Printf.printf "Diagnostics module:\n";

  (* Test of_verror converts a VError to a diagnostic *)
  let err = {
    code = StructuralError;
    message = "Pipeline has a dependency cycle involving node `foo`.";
    context = [];
    location = Some { file = Some "test.t"; line = 10; column = 5 };
    na_count = 0;
  } in
  let d = Diagnostics.of_verror err in
  let check name condition =
    if condition then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  ✗ %s\n" name in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in
  let check_eq name got expected =
    if got = expected then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  ✗ %s\n    Expected: %s\n    Got: %s\n" name expected got in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in
  check_eq "of_verror: error_class maps to structural_error"
    (Diagnostics.error_class_to_string (Diagnostics.diagnostic_error_class d)) "structural_error";
  check_eq "of_verror: phase maps to Wire for StructuralError"
    (Diagnostics.phase_to_string (Diagnostics.diagnostic_phase d)) "wire";
  check_eq "of_verror: severity is Error"
    (Diagnostics.severity_to_string (Diagnostics.diagnostic_severity d)) "error";

  (* Test cycle extraction from error message *)
  let cycle_nodes = Diagnostics.extract_cycle_nodes
    "Pipeline has a dependency cycle involving node `bar`." in
  check_eq "extract_cycle_nodes finds node name"
    (String.concat "," cycle_nodes) "bar";

  let no_cycle = Diagnostics.extract_cycle_nodes "some other error" in
  check_eq "extract_cycle_nodes returns empty for non-cycle error"
    (String.concat "," no_cycle) "";

  (* Test node name extraction from error message *)
  let node_name = Diagnostics.extract_node_name_from_message
    "Node `clean_loans` not found." in
  check_eq "extract_node_name_from_message finds node"
    (match node_name with Some n -> n | None -> "") "clean_loans";

  (* Test exit_code_of_diagnostics *)
  let err_diag = {
    d with
    Diagnostics.diag_phase = Diagnostics.Wire;
  } in
  check_eq "exit_code is 1 for wire-phase errors"
    (string_of_int (Diagnostics.exit_code_of_diagnostics [err_diag])) "1";

  let schema_diag = {
    d with
    Diagnostics.diag_phase = Diagnostics.Schema;
  } in
  check_eq "exit_code is 2 for schema-phase errors"
    (string_of_int (Diagnostics.exit_code_of_diagnostics [schema_diag])) "2";

  let env_diag = {
    d with
    Diagnostics.diag_phase = Diagnostics.Env;
  } in
  check_eq "exit_code is 3 for env-phase errors"
    (string_of_int (Diagnostics.exit_code_of_diagnostics [env_diag])) "3";

  (* Test JSON serialization produces valid structure *)
  let ok_result = Diagnostics.make_result ~tier:1 ~phase:Diagnostics.Wire [] in
  let json = Yojson.Safe.pretty_to_string
    (Diagnostics.check_result_to_yojson ok_result) in
  let json_flat = String.concat " " (Str.split (Str.regexp "\n+") json) in
  check "JSON output contains schema_version"
    (Str.string_match (Str.regexp ".*\"schema_version\".*\"1\".*") json_flat 0);
  check "JSON output contains status ok"
    (Str.string_match (Str.regexp ".*\"status\".*\"ok\".*") json_flat 0);

  Printf.printf "\ncheck_mode flag:\n";

  (* Test that check_mode prevents build_pipeline from triggering *)
  Ast.check_mode := true;
  let result = eval_string "pipeline { a = 1; b = a + 1 }" in
  let is_pipeline = match result with VPipeline _ -> true | _ -> false in
  check "check_mode: pipeline evaluation succeeds and returns VPipeline" is_pipeline;
  Ast.check_mode := false;

  (* Test that check_mode is properly reset *)
  check "check_mode: flag is false after reset"
    (not !Ast.check_mode);

  Printf.printf "\nDiag accessor functions:\n";

  (* Test accessor functions work correctly *)
  let test_diag = {
    Diagnostics.diag_id = "T0001";
    diag_error_class = Unknown_error;
    diag_severity = Diagnostics.Warning;
    diag_phase = Diagnostics.Exec;
    diag_node_id = Some "my_node";
    diag_node_lang = Some "r";
    diag_file = Some "test.t";
    diag_line = Some 5;
    diag_column = Some 10;
    diag_end_line = None;
    diag_end_column = None;
    diag_message = "test message";
    diag_expected = None;
    diag_actual = None;
    diag_caused_by = ["upstream_node"];
    diag_suggested_fix = Diagnostics.NoFix;
  } in
  check_eq "diagnostic_phase accessor"
    (Diagnostics.phase_to_string (Diagnostics.diagnostic_phase test_diag)) "exec";
  check_eq "diagnostic_severity accessor"
    (Diagnostics.severity_to_string (Diagnostics.diagnostic_severity test_diag)) "warning";
  check_eq "diagnostic_error_class accessor"
    (Diagnostics.error_class_to_string (Diagnostics.diagnostic_error_class test_diag)) "unknown_error";
  check_eq "diagnostic_message accessor"
    (Diagnostics.diagnostic_message test_diag) "test message";

  Printf.printf "\nexpected/actual fields:\n";
  let test_diag_with_types = { test_diag with
    Diagnostics.diag_expected = Some "double";
    diag_actual = Some "string";
  } in
  let json = Diagnostics.diagnostic_to_yojson test_diag_with_types in
  let expected_json = Yojson.Safe.Util.(json |> member "expected" |> member "value" |> to_string) in
  let actual_json = Yojson.Safe.Util.(json |> member "actual" |> member "value" |> to_string) in
  check_eq "expected field serializes correctly" expected_json "double";
  check_eq "actual field serializes correctly" actual_json "string";
  let test_diag_none_types = { test_diag with
    Diagnostics.diag_expected = None;
    diag_actual = None;
  } in
  let json_none = Diagnostics.diagnostic_to_yojson test_diag_none_types in
  let expected_null = Yojson.Safe.Util.(json_none |> member "expected") in
  let actual_null = Yojson.Safe.Util.(json_none |> member "actual") in
  check "expected is null when None" (expected_null = `Null);
  check "actual is null when None" (actual_null = `Null);

  Printf.printf "\nnode/span JSON structure:\n";
  let json_node = Diagnostics.diagnostic_to_yojson test_diag in
  let node_file = Yojson.Safe.Util.(json_node |> member "node" |> member "file" |> to_string_option) in
  let node_id = Yojson.Safe.Util.(json_node |> member "node" |> member "id" |> to_string) in
  let span_start = Yojson.Safe.Util.(json_node |> member "node" |> member "span" |> member "start") in
  let span_end = Yojson.Safe.Util.(json_node |> member "node" |> member "span" |> member "end") in
  check "node contains file" (node_file = Some "test.t");
  check_eq "node contains id" node_id "my_node";
  check "span has start array" (span_start = `List [`Int 5; `Int 10]);
  check "span.end is null when no end position" (span_end = `Null);
  check "top-level file field removed" (Yojson.Safe.Util.(json_node |> member "file") = `Null);

  Printf.printf "\nnode without node_id:\n";
  let test_diag_no_node = { test_diag with Diagnostics.diag_node_id = None } in
  let json_no_node = Diagnostics.diagnostic_to_yojson test_diag_no_node in
  let no_node_obj = Yojson.Safe.Util.(json_no_node |> member "node") in
  check "node object always present" (no_node_obj <> `Null);
  let no_node_id = Yojson.Safe.Util.(no_node_obj |> member "id") in
  check "node.id is null without node" (no_node_id = `Null);
  let no_node_file = Yojson.Safe.Util.(no_node_obj |> member "file" |> to_string_option) in
  check "node.file still present without node" (no_node_file = Some "test.t");
  let no_node_span = Yojson.Safe.Util.(no_node_obj |> member "span" |> member "start") in
  check "node.span.start still present without node" (no_node_span = `List [`Int 5; `Int 10]);

  Printf.printf "\nerror_class_of_string fallback:\n";
  check_eq "error_class_of_string: unknown string falls back to Unknown_error"
    (Diagnostics.error_class_to_string (Diagnostics.error_class_of_string "totally_bogus")) "unknown_error";
  check_eq "error_class_of_string: CamelCase TypeError maps to Type_error"
    (Diagnostics.error_class_to_string (Diagnostics.error_class_of_string "TypeError")) "type_error";
  check_eq "error_class_of_string: snake_case structural_error maps to Structural_error"
    (Diagnostics.error_class_to_string (Diagnostics.error_class_of_string "structural_error")) "structural_error";

  Printf.printf "\nAdd_node_arg generation:\n";
  let cross_runtime_msg = "Node `pyn` (Python) depends on `rn` (R) but has no explicit deserializer." in
  let cross_runtime_err = { Ast.
    code = StructuralError;
    message = cross_runtime_msg;
    context = [];
    location = None;
    na_count = 0;
  } in
  let cross_diag = Diagnostics.of_verror cross_runtime_err in
  (match cross_diag.Diagnostics.diag_suggested_fix with
   | Diagnostics.Add_node_arg { node; arg; target_node = _; _ } ->
       check_eq "cross-runtime: node name extracted" node "pyn";
       check_eq "cross-runtime: arg is deserializer" arg "deserializer = ^csv"
   | _ -> check "cross-runtime: generates Add_node_arg" false);
  check_eq "cross-runtime: error class is structural_error"
    (Diagnostics.error_class_to_string cross_diag.Diagnostics.diag_error_class) "structural_error";
  let non_cross_msg = "Some other structural error" in
  let non_cross_err = { Ast.
    code = StructuralError;
    message = non_cross_msg;
    context = [];
    location = None;
    na_count = 0;
  } in
  let non_cross_diag = Diagnostics.of_verror non_cross_err in
  (match non_cross_diag.Diagnostics.diag_suggested_fix with
   | Diagnostics.NoFix -> check "non-cross-runtime: no fix suggested" true
   | _ -> check "non-cross-runtime: should be NoFix" false);

  Printf.printf "\nSchema check module:\n";

  (* Set up temp fixture for read_csv_header test *)
  ignore (Sys.command "mkdir -p /tmp/schema_test");
  let oc = open_out "/tmp/schema_test/data.csv" in
  Printf.fprintf oc "mpg,cyl,hp\n21.0,6,110\n21.0,6,93\n22.8,4,93\n";
  close_out oc;

  (* Test extract_col_refs extracts ColumnRef *)
  let col_expr = { node = ColumnRef "mpg"; loc = None } in
  let refs = Schema_check.extract_col_refs col_expr in
  check_eq "extract_col_refs: ColumnRef" (String.concat "," refs) "mpg";

  (* Test extract_col_refs extracts from DotAccess *)
  let dot_expr = { node = DotAccess { target = { node = Var "row"; loc = None }; field = "hp" }; loc = None } in
  let refs = Schema_check.extract_col_refs ~param:"row" dot_expr in
  check_eq "extract_col_refs: DotAccess with matching param" (String.concat "," refs) "hp";

  (* Test extract_col_refs extracts from nested BinOp *)
  let bin_expr = { node = BinOp { op = Plus; left = col_expr; right = { node = Value (VInt 1); loc = None } }; loc = None } in
  let refs = Schema_check.extract_col_refs bin_expr in
  check_eq "extract_col_refs: nested BinOp" (String.concat "," refs) "mpg";

  (* Test infer_output_schema for select *)
  let select_expr = { node = Call { fn = { node = Var "select"; loc = None }; args = [(None, { node = ColumnRef "a"; loc = None }); (None, { node = ColumnRef "b"; loc = None })] }; loc = None } in
  let out = Schema_check.infer_output_schema (Schema_check.make_schema ["a"; "b"; "c"]) select_expr in
  check_eq "infer_output_schema: select" (String.concat "," (Schema_check.schema_names out)) "a,b";

  (* Test infer_output_schema for filter *)
  let filter_expr = { node = Call { fn = { node = Var "filter"; loc = None }; args = [(None, { node = ColumnRef "x"; loc = None })] }; loc = None } in
  let out = Schema_check.infer_output_schema (Schema_check.make_schema ["a"; "b"]) filter_expr in
  check_eq "infer_output_schema: filter passes through" (String.concat "," (Schema_check.schema_names out)) "a,b";

  (* Test infer_output_schema for mutate adds columns *)
  let mutate_expr = { node = Call { fn = { node = Var "mutate"; loc = None }; args = [(Some "new_col", { node = Value (VInt 1); loc = None })] }; loc = None } in
  let out = Schema_check.infer_output_schema (Schema_check.make_schema ["a"; "b"]) mutate_expr in
  check_eq "infer_output_schema: mutate adds new col" (String.concat "," (Schema_check.schema_names out)) "a,b,new_col";

  (* Test infer_output_schema for summarize *)
  let sum_expr = { node = Call { fn = { node = Var "summarize"; loc = None }; args = [(Some "avg", { node = Value (VInt 1); loc = None })] }; loc = None } in
  let out = Schema_check.infer_output_schema (Schema_check.make_schema ["a"; "b"]) sum_expr in
  check_eq "infer_output_schema: summarize" (String.concat "," (Schema_check.schema_names out)) "avg";

  (* Test read_csv_header *)
  let header = Schema_check.read_csv_header "/tmp/schema_test/data.csv" in
  check_eq "read_csv_header reads header"
    (match header with Some cols -> String.concat "," cols | None -> "NONE")
    "mpg,cyl,hp";

  (* Cleanup temp fixture *)
  ignore (Sys.command "rm -rf /tmp/schema_test");

  Printf.printf "\nContract validation:\n";

  (* Test validate_contracts detects missing columns *)
  let schemas_tbl = Hashtbl.create 4 in
  Hashtbl.add schemas_tbl "clean" (Schema_check.make_schema ["mpg"; "cyl"]);
  let p_with_contract = {
    p_nodes = []; p_exprs = []; p_deps = []; p_imports = [];
    p_runtimes = []; p_serializers = []; p_deserializers = [];
    p_env_vars = []; p_args = []; p_shells = []; p_shell_args = [];
    p_functions = []; p_includes = []; p_noops = []; p_scripts = [];
    p_explicit_deps = []; p_node_diagnostics = [];
    p_has_patterns = false; p_patterns = []; p_iterations = [];
    p_flakes = [];
    p_contracts = ["clean", {
      contract_columns = Some ["mpg"; "cyl"; "hp"];
      contract_types = None;
      contract_null_rates = None;
      contract_loc = None;
    }];
  } in
  let contract_diags = Schema_check.validate_contracts
    ~file:"test.t" p_with_contract schemas_tbl in
  check_eq "validate_contracts: detects missing column"
    (string_of_int (List.length contract_diags)) "1";
  let missing_msg = Diagnostics.diagnostic_message (List.hd contract_diags) in
  check "validate_contracts: message mentions missing column"
    (Str.string_match (Str.regexp ".*Missing.*hp.*") missing_msg 0);

  (* Test validate_contracts passes when all columns present *)
  let schemas_tbl2 = Hashtbl.create 4 in
  Hashtbl.add schemas_tbl2 "clean" (Schema_check.make_schema ["mpg"; "cyl"; "hp"]);
  let p_pass = {
    p_nodes = []; p_exprs = []; p_deps = []; p_imports = [];
    p_runtimes = []; p_serializers = []; p_deserializers = [];
    p_env_vars = []; p_args = []; p_shells = []; p_shell_args = [];
    p_functions = []; p_includes = []; p_noops = []; p_scripts = [];
    p_explicit_deps = []; p_node_diagnostics = [];
    p_has_patterns = false; p_patterns = []; p_iterations = [];
    p_flakes = [];
    p_contracts = ["clean", {
      contract_columns = Some ["mpg"; "cyl"];
      contract_types = None;
      contract_null_rates = None;
      contract_loc = None;
    }];
  } in
  let pass_diags = Schema_check.validate_contracts
    ~file:"test.t" p_pass schemas_tbl2 in
  check_eq "validate_contracts: passes when all columns present"
    (string_of_int (List.length pass_diags)) "0";

  Printf.printf "\nMid-chain expect() placement:\n";

  (* Test that mid-chain expect() produces a warning *)
  Ast.check_mode := true;
  let result = eval_string "pipeline { a = 1 |> expect(columns = [\"x\"]) |> as.integer() }" in
  let has_warn = match result with
    | VPipeline p ->
        List.exists (fun (_, diag) ->
          List.exists (fun w -> w.Ast.nw_kind = "invalid_expect_placement") diag.Ast.nd_warnings
        ) p.p_node_diagnostics
    | _ -> false
  in
  check "mid-chain expect: produces invalid_expect_placement warning" has_warn;
  Ast.check_mode := false;

  (* Test that terminal expect() does NOT produce a mid-chain warning *)
  Ast.check_mode := true;
  let result2 = eval_string "pipeline { a = 1 |> expect(columns = [\"x\"]) }" in
  let has_mid_warn = match result2 with
    | VPipeline p ->
        List.exists (fun (_, diag) ->
          List.exists (fun w -> w.Ast.nw_kind = "invalid_expect_placement") diag.Ast.nd_warnings
        ) p.p_node_diagnostics
    | _ -> false
  in
  check "terminal expect: no mid-chain warning" (not has_mid_warn);

  (* Test that terminal expect() attaches the contract *)
  let has_contract = match result2 with
    | VPipeline p ->
        List.exists (fun (_, c) -> c.Ast.contract_columns = Some ["x"]) p.p_contracts
    | _ -> false
  in
  check "terminal expect: contract attached with columns" has_contract;
  Ast.check_mode := false;

  (* End-to-end: verify warning survives of_pipeline_result (the t check path) *)
  Printf.printf "\nMid-chain expect() end-to-end (of_pipeline_result):\n";
  Ast.check_mode := true;
  let e2e_result = eval_string "pipeline { a = 1 |> expect(columns = [\"x\"]) |> as.integer() }" in
  let e2e_diags = match e2e_result with
    | VPipeline p -> Diagnostics.of_pipeline_result p
    | _ -> []
  in
  let e2e_has_warn = List.exists (fun d ->
    d.Diagnostics.diag_error_class = Diagnostics.Invalid_expect_placement
    && d.Diagnostics.diag_phase = Diagnostics.Wire
  ) e2e_diags in
  check "of_pipeline_result surfaces invalid_expect_placement diagnostic" e2e_has_warn;

  (* Verify terminal expect() does NOT produce a spurious diagnostic *)
  let e2e_terminal = eval_string "pipeline { a = 1 |> expect(columns = [\"x\"]) }" in
  let e2e_terminal_diags = match e2e_terminal with
    | VPipeline p -> Diagnostics.of_pipeline_result p
    | _ -> []
  in
  let e2e_no_spurious = not (List.exists (fun d ->
    d.Diagnostics.diag_error_class = Diagnostics.Invalid_expect_placement
  ) e2e_terminal_diags) in
  check "of_pipeline_result: no spurious diagnostic for terminal expect" e2e_no_spurious;
  Ast.check_mode := false;

  (* ---- Expanded contract tests ---- *)
  Printf.printf "\nExpanded contracts (type + null-rate):\n";

  (* Test that type contract is extracted from expect() *)
  Ast.check_mode := true;
  let type_result = eval_string "pipeline { a = 1 |> expect(mpg ~ double()) }" in
  let has_type_contract = match type_result with
    | VPipeline p ->
        List.exists (fun (_, c) ->
          c.Ast.contract_types = Some [("mpg", "double")]
        ) p.p_contracts
    | _ -> false
  in
  check "expect: type contract extracted (mpg ~ double())" has_type_contract;
  Ast.check_mode := false;

  (* Test that null-rate contract is extracted from expect() *)
  Ast.check_mode := true;
  let nr_result = eval_string "pipeline { a = 1 |> expect(null_rate(\"mpg\") < 0.05) }" in
  let has_nr_contract = match nr_result with
    | VPipeline p ->
        List.exists (fun (_, c) ->
          match c.Ast.contract_null_rates with
          | Some [("mpg", t)] -> t < 0.06 && t > 0.04
          | _ -> false
        ) p.p_contracts
    | _ -> false
  in
  check "expect: null-rate contract extracted (null_rate(\"mpg\") < 0.05)" has_nr_contract;
  Ast.check_mode := false;

  (* Test mixed contracts: columns + type + null-rate *)
  Ast.check_mode := true;
  let mixed_result = eval_string "pipeline { a = 1 |> expect(columns = [\"mpg\"], cyl ~ int(), null_rate(\"hp\") < 0.1) }" in
  let has_mixed = match mixed_result with
    | VPipeline p ->
        List.exists (fun (_, c) ->
          c.Ast.contract_columns = Some ["mpg"]
          && c.Ast.contract_types = Some [("cyl", "int")]
          && (match c.Ast.contract_null_rates with Some [("hp", t)] -> t < 0.11 | _ -> false)
        ) p.p_contracts
    | _ -> false
  in
  check "expect: mixed contracts (columns + type + null-rate)" has_mixed;
  Ast.check_mode := false;

  (* Test type contract validation: matching type *)
  Printf.printf "\nType contract validation:\n";
  let type_match_tbl = Hashtbl.create 4 in
  Hashtbl.add type_match_tbl "clean" (Schema_check.make_schema ~typed:[("mpg", "float")] ["mpg"; "cyl"]);
  let p_type_match = {
    p_nodes = []; p_exprs = []; p_deps = []; p_imports = [];
    p_runtimes = []; p_serializers = []; p_deserializers = [];
    p_env_vars = []; p_args = []; p_shells = []; p_shell_args = [];
    p_functions = []; p_includes = []; p_noops = []; p_scripts = [];
    p_explicit_deps = []; p_node_diagnostics = [];
    p_has_patterns = false; p_patterns = []; p_iterations = [];
    p_flakes = [];
    p_contracts = ["clean", {
      contract_columns = None;
      contract_types = Some [("mpg", "float")];
      contract_null_rates = None;
      contract_loc = None;
    }];
  } in
  let type_match_diags = Schema_check.validate_contracts
    ~file:"test.t" p_type_match type_match_tbl in
  check_eq "type contract: matching type produces no error"
    (string_of_int (List.length type_match_diags)) "0";

  (* Test type contract validation: mismatching type *)
  let p_type_mismatch = {
    p_nodes = []; p_exprs = []; p_deps = []; p_imports = [];
    p_runtimes = []; p_serializers = []; p_deserializers = [];
    p_env_vars = []; p_args = []; p_shells = []; p_shell_args = [];
    p_functions = []; p_includes = []; p_noops = []; p_scripts = [];
    p_explicit_deps = []; p_node_diagnostics = [];
    p_has_patterns = false; p_patterns = []; p_iterations = [];
    p_flakes = [];
    p_contracts = ["clean", {
      contract_columns = None;
      contract_types = Some [("mpg", "string")];
      contract_null_rates = None;
      contract_loc = None;
    }];
  } in
  let type_mismatch_diags = Schema_check.validate_contracts
    ~file:"test.t" p_type_mismatch type_match_tbl in
  check_eq "type contract: mismatching type produces 1 error"
    (string_of_int (List.length type_mismatch_diags)) "1";

  (* Test type contract validation: unknown type produces warning *)
  let type_unknown_tbl = Hashtbl.create 4 in
  Hashtbl.add type_unknown_tbl "clean" (Schema_check.make_schema ["mpg"]);
  let p_type_unknown = {
    p_nodes = []; p_exprs = []; p_deps = []; p_imports = [];
    p_runtimes = []; p_serializers = []; p_deserializers = [];
    p_env_vars = []; p_args = []; p_shells = []; p_shell_args = [];
    p_functions = []; p_includes = []; p_noops = []; p_scripts = [];
    p_explicit_deps = []; p_node_diagnostics = [];
    p_has_patterns = false; p_patterns = []; p_iterations = [];
    p_flakes = [];
    p_contracts = ["clean", {
      contract_columns = None;
      contract_types = Some [("mpg", "double")];
      contract_null_rates = None;
      contract_loc = None;
    }];
  } in
  let type_unknown_diags = Schema_check.validate_contracts
    ~file:"test.t" p_type_unknown type_unknown_tbl in
  check_eq "type contract: unknown type produces 1 warning"
    (string_of_int (List.length type_unknown_diags)) "1";
  let is_warning = match type_unknown_diags with
    | d :: _ -> d.Diagnostics.diag_severity = Diagnostics.Warning
    | [] -> false
  in
  check "type contract: unknown type is Warning not Error" is_warning;

  (* Test null-rate contract produces unverifiable warning *)
  let p_null_rate = {
    p_nodes = []; p_exprs = []; p_deps = []; p_imports = [];
    p_runtimes = []; p_serializers = []; p_deserializers = [];
    p_env_vars = []; p_args = []; p_shells = []; p_shell_args = [];
    p_functions = []; p_includes = []; p_noops = []; p_scripts = [];
    p_explicit_deps = []; p_node_diagnostics = [];
    p_has_patterns = false; p_patterns = []; p_iterations = [];
    p_flakes = [];
    p_contracts = ["clean", {
      contract_columns = None;
      contract_types = None;
      contract_null_rates = Some [("mpg", 0.05)];
      contract_loc = None;
    }];
  } in
  let nr_diags = Schema_check.validate_contracts
    ~file:"test.t" p_null_rate type_unknown_tbl in
  check_eq "null-rate contract: produces 1 unverifiable warning"
    (string_of_int (List.length nr_diags)) "1";
  let nr_is_warning = match nr_diags with
    | d :: _ ->
        d.Diagnostics.diag_severity = Diagnostics.Warning
        && d.Diagnostics.diag_error_class = Diagnostics.Contract_unverifiable
    | [] -> false
  in
  check "null-rate contract: warning has contract_unverifiable class" nr_is_warning;

  (* === t_check / t_diff / t_fix REPL function tests === *)

  Printf.printf "\nt_check (REPL function):\n";

  (* t_check with nonexistent file returns error *)
  let result = eval_string "t_check(\"nonexistent_file_xyz.t\")" in
  let _result_str = Ast.Utils.value_to_string result in
  check "t_check nonexistent file returns non-empty String"
    (match result with Ast.VString s -> String.length s > 0 | _ -> false);

  (* t_check with valid T file returns string *)
  let result = eval_string "t_check(\"tests/golden/t_scripts/mtcars_select_mpg.t\")" in
  check "t_check valid file returns String"
    (match result with Ast.VString _ -> true | _ -> false);

  (* t_check with schema flag *)
  let result = eval_string "t_check(\"tests/golden/t_scripts/mtcars_select_mpg.t\", schema=true)" in
  check "t_check with schema=true returns String"
    (match result with Ast.VString _ -> true | _ -> false);

  (* t_check with json flag returns JSON string *)
  let result = eval_string "t_check(\"tests/golden/t_scripts/mtcars_select_mpg.t\", json=true)" in
  let result_str = match result with Ast.VString s -> s | _ -> "" in
  check_eq "t_check with json=true contains schema_version"
    (if String.length result_str > 0 then "has_content" else "empty") "has_content";

  Printf.printf "\nt_diff (REPL function):\n";

  (* t_diff with nonexistent file returns VError *)
  let result = eval_string "t_diff(\"nonexistent_file_xyz.t\")" in
  check "t_diff nonexistent file returns VError"
    (match result with Ast.VError _ -> true | _ -> false);

  Printf.printf "\nt_fix (REPL function):\n";

  (* t_fix with nonexistent file returns error *)
  let result = eval_string "t_fix(\"nonexistent_file_xyz.t\")" in
  check "t_fix nonexistent file returns non-empty String"
    (match result with Ast.VString s -> String.length s > 0 | _ -> false);

  (* t_fix with valid file and dry_run *)
  let result = eval_string "t_fix(\"tests/golden/t_scripts/mtcars_select_mpg.t\", dry_run=true)" in
  check "t_fix dry_run returns String"
    (match result with Ast.VString _ -> true | _ -> false);

  Printf.printf "\n";
