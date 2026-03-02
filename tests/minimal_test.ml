(* tests/minimal_test.ml *)
let pass_count = ref 0
let fail_count = ref 0

let eval_string input =
  let env = Packages.init_env () in
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
    Printf.printf "  success %s\n" name
  end else begin
    incr fail_count;
    Printf.printf "  failure %s\n    Expected: %s\n    Got:      %s\n" name expected result
  end

let () =
  Printf.printf "\n=== Minimal T Tests ===\n\n";
  Test_arithmetic.run_tests pass_count fail_count eval_string eval_string_env test;
  let total = !pass_count + !fail_count in
  Printf.printf "=== Results: %d/%d passed ===\n" !pass_count total;
  if !fail_count > 0 then exit 1 else exit 0
