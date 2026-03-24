let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
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
    {|match([1, 2]) { [head, ..tail] => head, [] => 0 }; head|}
    {|Error(NameError: "Name `head` is not defined.")|};
  print_newline ()
