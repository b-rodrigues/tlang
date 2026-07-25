(* tests/test_runner.ml *)
(* Test orchestrator — calls into per-module test files *)


let pass_count = ref 0
let fail_count = ref 0
let failures = ref []

(* Strict mode: detect modules that produce 0 assertions *)
let strict_mode = try Sys.getenv "TLANG_TEST_STRICT" = "1" with Not_found -> false
let empty_modules = ref []

let run_module name fn =
  let before_pass = !pass_count in
  let before_fail = !fail_count in
  fn ();
  let assertions = (!pass_count - before_pass) + (!fail_count - before_fail) in
  if strict_mode && assertions = 0 then begin
    Printf.printf "  ⚠ STRICT: %s produced 0 assertions\n" name;
    empty_modules := name :: !empty_modules
  end

let () =
  Eval.show_warnings := false

let shared_env = Packages.init_env ()

let eval_string input =
  let lexbuf = Lexing.from_string input in
  let program = Parser.program Lexer.token lexbuf in
  let (result, _env) = Eval.eval_program ~resilient:false program shared_env in
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
  Printf.printf "\n=== T Language Tests ===\n";
  if strict_mode then Printf.printf "(strict mode enabled)\n";
  Printf.printf "\n";

  let run name fn =
    run_module name (fun () -> fn pass_count fail_count failures eval_string eval_string_env test)
  in

  (* Core tests *)
  run "Test_arithmetic" Test_arithmetic.run_tests;
  run "Test_comparisons" Test_comparisons.run_tests;
  run "Test_logical" Test_logical.run_tests;
  run "Test_in" Test_in.run_tests;
  run "Test_operators" Test_operators.run_tests;
  run "Test_scalar_strictness" Test_scalar_strictness.run_tests;
  run "Test_typing_mode" Test_typing_mode.run_tests;
  run "Test_bitwise_error" Test_bitwise_error.run_tests;
  run "Test_variables" Test_variables.run_tests;
  run "Test_functions" Test_functions.run_tests;
  run "Test_strings" Test_strings.run_tests;
  run "Test_pipe" Test_pipe.run_tests;
  run "Test_ifelse" Test_ifelse.run_tests;
  run "Test_match" Test_match.run_tests;
  run "Test_lists" Test_lists.run_tests;
  run "Test_dicts" Test_dicts.run_tests;
  run "Test_builtins" Test_builtins.run_tests;
  run "Test_chrono" Test_chrono.run_tests;
  run "Test_rng" Test_rng.run_tests;
  run "Test_shell" Test_shell.run_tests;
  run "Test_lsp_support" Test_lsp_support.run_tests;
  run "Test_sh_node" Test_sh_node.run_tests;

  (* Base tests *)
  run "Test_converters" Test_converters.run_tests;
  run "Test_na" Test_na.run_tests;
  run "Test_na_edge_cases" Test_na_edge_cases.run_tests;
  run "Test_errors" Test_errors.run_tests;
  run "Test_expect_equal" Test_expect_equal.run_tests;
  run "Test_expect_more" Test_expect_more.run_tests;
  run "Test_expect_condition" Test_expect_condition.run_tests;
  run "Test_expect_pipeline" Test_expect_pipeline.run_tests;
  run "Test_expect_pass_fail_msg" Test_expect_pass_fail_msg.run_tests;
  run "Test_expect_ds_coverage" Test_expect_ds_coverage.run_tests;
  run "Test_fetchurl" Test_fetchurl.run_tests;

  (* Domain-specific tests *)
  run "Test_dataframe" Test_dataframe.run_tests;
  run "Test_pipeline" Test_pipeline.run_tests;
  run "Test_colcraft" Test_colcraft.run_tests;
  run "Test_colcraft_coverage" Test_colcraft_coverage.run_tests;
  run "Test_window" Test_window.run_tests;
  run "Test_math" Test_math.run_tests;
  run "Test_stats" Test_stats.run_tests;
  run "Test_stats_coverage" Test_stats_coverage.run_tests;
  run "Test_pmml_random_forest" Test_pmml_random_forest.run_tests;
  run "Test_pmml_io" Test_pmml_io.run_tests;
  run "Test_pmml_xgboost" Test_pmml_xgboost.run_tests;
  run "Test_pmml_lightgbm" Test_pmml_lightgbm.run_tests;
  run "Test_onnx_native" Test_onnx_native.run_tests;
  run "Test_broom_golden" Test_broom_golden.run_tests;
  run "Test_explain_tests" Test_explain_tests.run_tests;
  run "Test_cli" Test_cli.run_tests;

  (* Phase 8: Stabilization tests *)
  run "Test_golden" Test_golden.run_tests;
  run "Test_boolean_golden" Test_boolean_golden.run_tests;
  run "Test_core_semantics" Test_core_semantics.run_tests;

  (* Arrow integration tests *)
  run "Test_arrow_integration" Test_arrow_integration.run_tests;
  run "Test_owl_bridge" Test_owl_bridge.run_tests;
  run "Test_arrow_performance" Test_arrow_performance.run_tests;

  (* Week 2: Edge case hardening + large dataset tests *)
  run "Test_colcraft_edge_cases" Test_colcraft_edge_cases.run_tests;
  run "Test_window_edge_cases" Test_window_edge_cases.run_tests;
  run "Test_formula_edge_cases" Test_formula_edge_cases.run_tests;
  run "Test_large_datasets" Test_large_datasets.run_tests;
  run "Test_error_recovery" Test_error_recovery.run_tests;

  (* Package manager tests *)
  run "Test_package_manager" Test_package_manager.run_tests;

  (* Lens tests *)
  run "Test_lens" Test_lens.run_tests;

  (* First-Class Serializers *)
  run "Test_serializers" Test_serializers.run_tests;

  (* Quotation tests *)
  run "Test_quotation" Test_quotation.run_tests;

  (* Pipeline operations tests (Phase 1 & 2) *)
  run "Test_pipeline_ops" Test_pipeline_ops.run_tests;

  (* Explicit deps tests *)
  run "Test_explicit_deps" Test_explicit_deps.run_tests;

  (* Pipeline comments and annotations *)
  run "Test_pipeline_comments" Test_pipeline_comments.run_tests;

  (* Nix emission utilities *)
  run "Test_nix_emit" Test_nix_emit.run_tests;

  (* ImportFileFrom tests *)
  run "Test_import_file_from" Test_import_file_from.run_tests;
  
  (* Structural Integrity & Error category tests *)
  run "Test_structural_integrity" Test_structural_integrity.run_tests;
  run "Test_agent_scaffold" Test_agent_scaffold.run_tests;
  run "Test_coverage_boost" Test_coverage_boost.run_tests;
  run "Test_misc_coverage" Test_misc_coverage.run_tests;
  run "Test_dataframe_diff" Test_dataframe_diff.run_tests;
  run "Test_model_diff" Test_model_diff.run_tests;
  run "Test_scalar_diff" Test_scalar_diff.run_tests;
  run "Test_generic_diff" Test_generic_diff.run_tests;
  run "Test_pipeline_diff" Test_pipeline_diff.run_tests;
  run "Test_builder_diff" Test_builder_diff.run_tests;

  (* t check / Diagnostics tests *)
  run "Test_check" Test_check.run_tests;
  flush stdout;
  run "Test_fix" Test_fix.run_tests;
  flush stdout;

  (* NDJSON streaming tests *)
  run "Test_ndjson" Test_ndjson.run_tests;

  (* Summary *)
  let total = !pass_count + !fail_count in
  Printf.printf "\n=== Results: %d/%d passed ===\n" !pass_count total;
  if strict_mode && !empty_modules <> [] then begin
    Printf.printf "\nSTRICT MODE: %d modules produced 0 assertions:\n" (List.length !empty_modules);
    List.iter (fun m -> Printf.printf "  - %s\n" m) (List.rev !empty_modules)
  end;
  if !fail_count > 0 then begin
    Printf.printf "\nFAILURE SUMMARY:\n";
    List.iter (fun msg -> Printf.printf "%s\n" msg) (List.rev !failures);
    Printf.printf "FAILED: %d tests failed\n" !fail_count;
    exit 1
  end else
    Printf.printf "All tests passed!\n"
