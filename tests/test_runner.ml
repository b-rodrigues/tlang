(* tests/test_runner.ml *)
(* Test orchestrator — calls into per-module test files *)


let pass_count = ref 0
let fail_count = ref 0
let failures = ref []

let () =
  Eval.show_warnings := false

let eval_string input =
  let env = Packages.init_env () in
  let lexbuf = Lexing.from_string input in
  let program = Parser.program Lexer.token lexbuf in
  let (result, _env) = Eval.eval_program ~resilient:false program env in
  result

let eval_string_env input env =
  let lexbuf = Lexing.from_string input in
  let program = Parser.program Lexer.token lexbuf in
  Eval.eval_program ~resilient:false program env

let strip_location s =
  let re = Str.regexp "\\[[^]]*L[0-9]+:C[0-9]+\\] " in
  Str.global_replace re "" s

let test name input expected =
  let result = try
    let v = eval_string input in
    Ast.Utils.value_to_string v
  with e ->
    Printf.sprintf "EXCEPTION: %s" (Printexc.to_string e)
  in
  let result_norm = strip_location result in
  let expected_norm = strip_location expected in
  
  let match_found = 
    if result_norm = expected_norm then true
    else try
      let _ = Str.search_forward (Str.regexp expected_norm) result_norm 0 in
      true
    with _ -> false
  in

  if match_found then begin
    incr pass_count;
    Printf.printf "  ✓ %s\n" name
  end else begin
    incr fail_count;
    let msg = Printf.sprintf "  ✗ %s\n    Expected (regex): %s\n    Got:               %s\n" name expected result in
    failures := msg :: !failures;
    Printf.printf "%s" msg
  end

let () =
  Printf.printf "\n=== T Language Tests ===\n\n";

  (* Core tests *)
  Test_arithmetic.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_comparisons.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_logical.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_in.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_operators.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_scalar_strictness.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_typing_mode.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_bitwise_error.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_variables.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_functions.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_strings.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_pipe.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_ifelse.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_match.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_lists.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_dicts.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_builtins.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_chrono.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_shell.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_lsp_support.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_sh_node.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Base tests *)
  Test_converters.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_na.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_na_edge_cases.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_errors.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Domain-specific tests *)
  Test_dataframe.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_pipeline.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_colcraft.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_window.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_math.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_stats.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_pmml_random_forest.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_pmml_io.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_pmml_xgboost.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_pmml_lightgbm.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_onnx_native.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_broom_golden.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_explain_tests.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_cli.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Phase 8: Stabilization tests *)
  Test_golden.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_boolean_golden.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_core_semantics.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Arrow integration tests *)
  Test_arrow_integration.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_owl_bridge.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_arrow_performance.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Week 2: Edge case hardening + large dataset tests *)
  Test_colcraft_edge_cases.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_window_edge_cases.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_formula_edge_cases.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_large_datasets.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_error_recovery.run_tests pass_count fail_count eval_string eval_string_env test;


  (* Package manager tests *)
  Test_package_manager.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Lens tests *)
  Test_lens.run_tests pass_count fail_count eval_string eval_string_env test;

  (* First-Class Serializers *)
  Test_serializers.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Quotation tests *)
  Test_quotation.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Pipeline operations tests (Phase 1 & 2) *)
  Test_pipeline_ops.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Explicit deps tests *)
  Test_explicit_deps.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Pipeline comments and annotations *)
  Test_pipeline_comments.run_tests pass_count fail_count eval_string eval_string_env test;

  (* ImportFileFrom tests *)
  Test_import_file_from.run_tests pass_count fail_count eval_string eval_string_env test;
  
  (* Structural Integrity & Error category tests *)
  Test_structural_integrity.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Summary *)
  let total = !pass_count + !fail_count in
  Printf.printf "\n=== Results: %d/%d passed ===\n" !pass_count total;
  if !fail_count > 0 then begin
    Printf.printf "\nFAILURE SUMMARY:\n";
    List.iter (fun msg -> Printf.printf "%s\n" msg) (List.rev !failures);
    Printf.printf "FAILED: %d tests failed\n" !fail_count;
    exit 1
  end else
    Printf.printf "All tests passed!\n"
