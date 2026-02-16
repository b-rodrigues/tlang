let parse_program input =
  let lexbuf = Lexing.from_string input in
  Parser.program Lexer.token lexbuf

let run_tests pass_count fail_count _eval_string _eval_string_env test =
  Printf.printf "Typing mode and typed lambda syntax:\n";

  (* Test typed lambda with explicit return type - body must be in braces *)
  test "typed lambda with return annotation parses and runs"
    "add = \\(x: Int, y: Int) -> Int { x + y }; add(2, 3)"
    "5";

  (* Test untyped lambda - body can be any expression *)
  test "untyped lambda parses and runs"
    "add = \\(x, y) x + y; add(2, 3)"
    "5";

  let report name ok =
    if ok then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  ✗ %s\n" name
    end
  in

  let strict_ok =
    match Typecheck.validate_program ~mode:Typecheck.Strict
      (parse_program "id = \\(x: Int) -> Int { x }") with
    | Ok () -> true
    | Error _ -> false
  in
  report "strict mode accepts annotated top-level lambda" strict_ok;

  let strict_bad =
    match Typecheck.validate_program ~mode:Typecheck.Strict
      (parse_program "id = \\(x) x") with
    | Ok () -> false
    | Error _ -> true
  in
  report "strict mode rejects unannotated top-level lambda" strict_bad;

  (* Test generic parameter validation *)
  let generic_ok =
    match Typecheck.validate_program ~mode:Typecheck.Strict
      (parse_program "id = \\<T>(x: T) -> T { x }") with
    | Ok () -> true
    | Error _ -> false
  in
  report "strict mode accepts generic lambda with declared type vars" generic_ok;

  let generic_bad =
    match Typecheck.validate_program ~mode:Typecheck.Strict
      (parse_program "id = \\(x: T) -> T { x }") with
    | Ok () -> false
    | Error _ -> true
  in
  report "strict mode rejects generic lambda without declared type vars" generic_bad;

  print_newline ()
