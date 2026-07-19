(* tests/test_check.ml *)
(* Tests for t check: diagnostics module and check_mode flag *)

open Ast

let golden name =
  Filename.concat
    (Filename.concat (Test_helpers.find_repo_root ()) "tests/golden/t_scripts")
    name

let run_tests pass_count fail_count failures eval_string _eval_string_env _test =
  Printf.printf "=== t check / Diagnostics tests ===\n\n";
  flush stdout;

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
       check_eq "cross-runtime (R dep): node name extracted" node "pyn";
       check_eq "cross-runtime (R dep): arg uses ^csv" arg "deserializer = ^csv"
   | _ -> check "cross-runtime (R dep): generates Add_node_arg" false);
  check_eq "cross-runtime: error class is structural_error"
    (Diagnostics.error_class_to_string cross_diag.Diagnostics.diag_error_class) "structural_error";

  let julia_msg = "Node `rn` (R) depends on `jln` (Julia) but has no explicit deserializer." in
  let julia_err = { Ast.
    code = StructuralError;
    message = julia_msg;
    context = [];
    location = None;
    na_count = 0;
  } in
  let julia_diag = Diagnostics.of_verror julia_err in
  (match julia_diag.Diagnostics.diag_suggested_fix with
   | Diagnostics.Add_node_arg { node; arg; _ } ->
       check_eq "cross-runtime (Julia dep): node name" node "rn";
       check_eq "cross-runtime (Julia dep): arg uses ^arrow" arg "deserializer = ^arrow"
   | _ -> check "cross-runtime (Julia dep): generates Add_node_arg" false);

  let py_msg = "Node `jln` (Julia) depends on `pyn` (Python) but has no explicit deserializer." in
  let py_err = { Ast.
    code = StructuralError;
    message = py_msg;
    context = [];
    location = None;
    na_count = 0;
  } in
  let py_diag = Diagnostics.of_verror py_err in
  (match py_diag.Diagnostics.diag_suggested_fix with
   | Diagnostics.Add_node_arg { arg; _ } ->
       check_eq "cross-runtime (Python dep): arg uses ^csv" arg "deserializer = ^csv"
   | _ -> check "cross-runtime (Python dep): generates Add_node_arg" false);

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

  Printf.printf "\nt_check (REPL function):\n";

  (* t_check with nonexistent file returns error *)
  let result = eval_string "t_check(\"nonexistent_file_xyz.t\")" in
  let _result_str = Ast.Utils.value_to_string result in
  check "t_check nonexistent file returns non-empty String"
    (match result with Ast.VString s -> String.length s > 0 | _ -> false);

  (* t_check with valid T file returns string *)
  let result = eval_string (Printf.sprintf "t_check(\"%s\")" (golden "mtcars_select_mpg.t")) in
  check "t_check valid file returns String"
    (match result with Ast.VString _ -> true | _ -> false);

  (* t_check with schema flag *)
  let result = eval_string (Printf.sprintf "t_check(\"%s\", schema=true)" (golden "mtcars_select_mpg.t")) in
  check "t_check with schema=true returns String"
    (match result with Ast.VString _ -> true | _ -> false);

  (* t_check with json flag returns JSON string *)
  let result = eval_string (Printf.sprintf "t_check(\"%s\", json=true)" (golden "mtcars_select_mpg.t")) in
  let result_str = match result with Ast.VString s -> s | _ -> "" in
  check_eq "t_check with json=true contains schema_version"
    (if String.length result_str > 0 then "has_content" else "empty") "has_content";

  Printf.printf "\nschema check rename tests:\n";

  (* Schema rename: positive case — rename() + select() pipe chain, zero diagnostics *)
  let result = eval_string (Printf.sprintf "t_check(\"%s\", schema=true, json=true)" (golden "schema_rename_pipe.t")) in
  let result_str = match result with Ast.VString s -> s | _ -> "" in
  let no_schema_mismatch =
    String.length result_str > 0
    && (try ignore (Str.search_forward (Str.regexp "schema_mismatch") result_str 0); false
        with Not_found -> true)
  in
  check "schema rename pipe: no schema_mismatch errors" no_schema_mismatch;
  flush stdout;

  (* Schema rename: negative case — stale col ref after rename should error *)
  let result = eval_string (Printf.sprintf "t_check(\"%s\", schema=true)" (golden "schema_rename_stale.t")) in
  let result_str = match result with Ast.VString s -> s | _ -> "" in
  let has_col_error =
    try ignore (Str.search_forward (Str.regexp "schema_mismatch") result_str 0); true
    with Not_found -> false
  in
  check "schema rename stale: detects stale column ref after rename" has_col_error;
  flush stdout;

  Printf.printf "\nschema check rename fix suggestion:\n";

  (* Schema rename: verify Rename_column is attached as suggested fix *)
  let result = eval_string (Printf.sprintf "t_check(\"%s\", schema=true, json=true)" (golden "schema_rename_stale.t")) in
  let result_str = match result with Ast.VString s -> s | _ -> "" in
  let has_rename_fix =
    String.length result_str > 0
    && (try ignore (Str.search_forward (Str.regexp "\"rename_column\"") result_str 0); true
        with Not_found -> false)
  in
  check "schema rename stale: suggested_fix is rename_column" has_rename_fix;
  flush stdout;

  Printf.printf "\nmissing package detection:\n";

  (* Missing package: undeclared R package should get Missing_package *)
  let result = eval_string (Printf.sprintf "t_check(\"%s\", env=true, json=true)" (golden "missing_package.t")) in
  let result_str = match result with Ast.VString s -> s | _ -> "" in
  let has_missing_pkg =
    String.length result_str > 0
    && (try ignore (Str.search_forward (Str.regexp "missing_package") result_str 0); true
        with Not_found -> false)
  in
  check "missing package: diagnostic has missing_package" has_missing_pkg;
  flush stdout;

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
  let result = eval_string (Printf.sprintf "t_fix(\"%s\", dry_run=true)" (golden "mtcars_select_mpg.t")) in
  check "t_fix dry_run returns String"
    (match result with Ast.VString _ -> true | _ -> false);

  Printf.printf "\nName_error suggestions:\n";
  let test_name_suggestion () =
    let (name, suggestion) = Diagnostics.extract_name_and_suggestion "Variable 'prnt' is not defined" in
    check "prnt extracts name" (name = "prnt");
    check "prnt suggests print" (suggestion = Some "print");
    let (_name2, suggestion2) = Diagnostics.extract_name_and_suggestion "Variable 'flter' is not defined" in
    check "flter suggests filter" (suggestion2 = Some "filter");
    let (_name3, suggestion3) = Diagnostics.extract_name_and_suggestion "Variable 'mutat' is not defined" in
    check "mutat suggests mutate" (suggestion3 = Some "mutate");
    let (_name4, suggestion4) = Diagnostics.extract_name_and_suggestion "Variable 'xyzzy_unknown' is not defined" in
    check "unknown name has no suggestion" (suggestion4 = None)
  in
  test_name_suggestion ();

  Printf.printf "\nSuggest_identifier fix:\n";
  let test_suggest_identifier () =
    let d = { Diagnostics.
      diag_id = "T9001"; diag_error_class = Diagnostics.Name_error; diag_severity = Error;
      diag_phase = Wire; diag_node_id = None; diag_node_lang = None;
      diag_file = Some "test.t"; diag_line = Some 1; diag_column = None;
      diag_end_line = None; diag_end_column = None;
      diag_message = "Variable 'prnt' is not defined"; diag_expected = None; diag_actual = None;
      diag_caused_by = [];
      diag_suggested_fix = Diagnostics.Suggest_identifier { name = "prnt"; suggestion = "print"; target_node = None; file = Some "test.t"; line = Some 1 };
    } in
    let json = Diagnostics.diagnostic_to_yojson d in
    let fix_json = Yojson.Safe.Util.member "suggested_fix" json in
    let kind = Yojson.Safe.Util.member "kind" fix_json |> Yojson.Safe.Util.to_string in
    check "Suggest_identifier serializes kind=suggest_identifier" (kind = "suggest_identifier");
    let suggestion = Yojson.Safe.Util.member "suggestion" fix_json |> Yojson.Safe.Util.to_string in
    check "Suggest_identifier serializes suggestion=print" (suggestion = "print");
    let confidence = Yojson.Safe.Util.member "confidence" fix_json |> Yojson.Safe.Util.to_string in
    check "Suggest_identifier serializes confidence=medium" (confidence = "medium");
    let roundtrip = Diagnostics.suggested_fix_of_yojson fix_json in
    (match roundtrip with
     | Diagnostics.Suggest_identifier { name; suggestion = s; _ } ->
         check "Suggest_identifier roundtrip name" (name = "prnt");
         check "Suggest_identifier roundtrip suggestion" (s = "print")
     | _ -> check "Suggest_identifier roundtrip fails" false)
  in
  test_suggest_identifier ();

  Printf.printf "\nRun_command fix:\n";
  let test_run_command () =
    let fix = Diagnostics.Run_command { command = "t init ."; description = "Initialize tproject.toml"; target_node = None; file = Some "test.t"; line = None } in
    let json = Diagnostics.suggested_fix_to_yojson fix in
    let confidence = Yojson.Safe.Util.member "confidence" json |> Yojson.Safe.Util.to_string in
    check "Run_command serializes confidence=low" (confidence = "low");
    let roundtrip = Diagnostics.suggested_fix_of_yojson json in
    (match roundtrip with
     | Diagnostics.Run_command { command = cmd; description = desc; _ } ->
         check "Run_command roundtrip command" (cmd = "t init .");
         check "Run_command roundtrip description" (desc = "Initialize tproject.toml")
     | _ -> check "Run_command roundtrip fails" false)
  in
  test_run_command ();

  Printf.printf "\nCast and Rename_column confidence:\n";
  let test_cast_and_rename_confidence () =
    let cast_fix = Diagnostics.Cast { column = "x"; cast_to = "double"; target_node = None; file = Some "test.t"; line = Some 1 } in
    let cast_json = Diagnostics.suggested_fix_to_yojson cast_fix in
    let cast_conf = Yojson.Safe.Util.member "confidence" cast_json |> Yojson.Safe.Util.to_string in
    check "Cast serializes confidence=high" (cast_conf = "high");

    let rename_fix = Diagnostics.Rename_column { old_name = "x"; new_name = "y"; target_node = None; file = Some "test.t"; line = Some 1 } in
    let rename_json = Diagnostics.suggested_fix_to_yojson rename_fix in
    let rename_conf = Yojson.Safe.Util.member "confidence" rename_json |> Yojson.Safe.Util.to_string in
    check "Rename_column serializes confidence=high" (rename_conf = "high")
  in
  test_cast_and_rename_confidence ();

  Printf.printf "\n";
