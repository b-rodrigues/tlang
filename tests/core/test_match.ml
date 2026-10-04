let run_tests pass_count fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "Match:\n";
  test "match empty list"
    {|match([]) { [] => "Empty", [head, ..tail] => str_format("Starts with {head}", [head: head]) }|}
    {|"Empty"|};
  test "match list head-tail binding"
    {|match([1, 2, 3]) { [head, ..tail] => head + length(tail), [] => 0 }|}
    "3";
  test "match error message binding"
    {|match(error("boom")) { Error { msg } => msg, _ => "ok" }|}
    {|"boom"|};
  test "match NA"
    {|match(NA) { NA => "Missing", _ => "Other" }|}
    {|"Missing"|};
  test "match no pattern"
    {|match(1) { NA => "missing" }|}
    {|Error(MatchError: "Match expression did not match any pattern.")|};
  test "match bindings are scoped to the selected arm"
    {|match([1, 2]) { [h, ..t] => h, [] => 0 }; h|}
    {|Name `h` is not defined.|};
  let contains_sub s sub =
    let sl = String.length s in
    let bl = String.length sub in
    if bl = 0 then true
    else
      let rec loop i =
        if i + bl > sl then false
        else if String.sub s i bl = sub then true
        else loop (i + 1)
      in
      loop 0
  in
  let diags_of code =
    let lexbuf = Lexing.from_string code in
    let program = Parser.program Lexer.token lexbuf in
    Check_utils.match_exhaustiveness_diagnostics program "test.t"
  in
  let check_warn name code expect_count expect_sub =
    let diags = diags_of code in
    let n = List.length diags in
    let sub_ok =
      match expect_sub with
      | None -> true
      | Some sub ->
          List.exists (fun d -> contains_sub d.Diagnostics.diag_message sub) diags
    in
    let sev_ok =
      List.for_all (fun d -> d.Diagnostics.diag_severity = Diagnostics.Warning) diags
    in
    if n = expect_count && sub_ok && sev_ok then begin
      incr pass_count; Printf.printf "  SUCCESS %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  FAILURE %s (expected %d warnings, got %d)\n" name expect_count n
    end
  in
  check_warn "match error without Error arm warns"
    {|match(error("boom")) { NA => "x" }|} 1 (Some "Error");
  check_warn "match error with Error arm stays silent"
    {|match(error("boom")) { Error { msg } => msg }|} 0 None;
  check_warn "match error with catch-all stays silent"
    {|match(error("boom")) { Error { msg } => msg, _ => "ok" }|} 0 None;
  check_warn "match NA without NA arm warns"
    {|match(NA) { Error { e } => "e" }|} 1 (Some "NA");
  check_warn "match NA with NA arm stays silent"
    {|match(NA) { NA => "m", _ => "o" }|} 0 None;
  check_warn "match Int stays silent (unknown family)"
    {|match(1) { NA => "missing" }|} 0 None;
  check_warn "match variable stays silent (unknown scrutinee)"
    {|match(x) { NA => "a" }|} 0 None;
  check_warn "match inside assignment warns"
    {|y = match(error("b")) { NA => 1 }|} 1 (Some "Error");
  print_newline ()
