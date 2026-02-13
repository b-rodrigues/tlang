(* tests/test_runner.ml *)
(* Test orchestrator — calls into per-module test files *)

let pass_count = ref 0
let fail_count = ref 0

let eval_string input =
  let env = Eval.initial_env () in
  let lexbuf = Lexing.from_string input in
  let program = Parser.program Lexer.token lexbuf in
  let (result, _env) = Eval.eval_program program env in
  result

let eval_string_env input env =
  let lexbuf = Lexing.from_string input in
  let program = Parser.program Lexer.token lexbuf in
  Eval.eval_program program env

let test name input expected =
  let result = try
    let v = eval_string input in
    Ast.Utils.value_to_string v
  with e ->
    Printf.sprintf "EXCEPTION: %s" (Printexc.to_string e)
  in
  if result = expected then begin
    incr pass_count;
    Printf.printf "  ✓ %s\n" name
  end else begin
    incr fail_count;
    Printf.printf "  ✗ %s\n    Expected: %s\n    Got:      %s\n" name expected result
  end

let () =
  Printf.printf "\n=== T Language Tests ===\n\n";

  (* Core tests *)
  (* Core tests *)
  Test_arithmetic.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_comparisons.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_logical.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_in.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_operators.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_variables.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_functions.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_pipe.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_ifelse.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_lists.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_dicts.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_builtins.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Base tests *)
  Test_na.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_errors.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Domain-specific tests *)
  Test_dataframe.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_pipeline.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_colcraft.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_window.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_math.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_stats.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_broom_golden.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_explain_tests.run_tests pass_count fail_count eval_string eval_string_env test;
  Test_cli.run_tests pass_count fail_count eval_string eval_string_env test;

  (* Phase 8: Stabilization tests *)
  Test_golden.run_tests pass_count fail_count eval_string eval_string_env test;
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



  (* Summary *)
  let total = !pass_count + !fail_count in
  Printf.printf "=== Results: %d/%d passed ===\n" !pass_count total;
  if !fail_count > 0 then begin
    Printf.printf "FAILED: %d tests failed\n" !fail_count;
    exit 1
  end else
    Printf.printf "All tests passed!\n"
