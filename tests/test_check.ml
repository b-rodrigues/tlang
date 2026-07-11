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
    (Diagnostics.diagnostic_error_class d) "structural_error";
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
    diag_error_class = "test_error";
    diag_severity = Diagnostics.Warning;
    diag_phase = Diagnostics.Exec;
    diag_node_id = Some "my_node";
    diag_node_lang = Some "r";
    diag_file = Some "test.t";
    diag_line = Some 5;
    diag_column = Some 10;
    diag_message = "test message";
    diag_caused_by = ["upstream_node"];
    diag_suggested_fix = Diagnostics.NoFix;
  } in
  check_eq "diagnostic_phase accessor"
    (Diagnostics.phase_to_string (Diagnostics.diagnostic_phase test_diag)) "exec";
  check_eq "diagnostic_severity accessor"
    (Diagnostics.severity_to_string (Diagnostics.diagnostic_severity test_diag)) "warning";
  check_eq "diagnostic_error_class accessor"
    (Diagnostics.diagnostic_error_class test_diag) "test_error";
  check_eq "diagnostic_message accessor"
    (Diagnostics.diagnostic_message test_diag) "test message";

  Printf.printf "\n";
