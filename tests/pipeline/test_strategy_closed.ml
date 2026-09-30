(* tests/pipeline/test_strategy_closed.ml *)
(* Closed serializer/deserializer strategies (spec path item 2).
   Bare names outside the built-in set fail where a strategy is
   expected; custom functions must be quoted with custom("name").
   Fresh environment per test so nothing leaks across cases. *)

let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test test_env =
  Printf.printf "Closed strategies:\n";
  let fresh () = Packages.init_env () in
  test "strategy baseline arithmetic"
    "1 + 2"
    "3";
  test_env (fresh ()) "custom quotes a function name"
    {|custom("write_pkl")|}
    "write_pkl";
  test_env (fresh ()) "custom rejects non-string names"
    {|custom(42)|}
    "expects a String function name";
  test_env (fresh ()) "custom rejects wrong arity"
    {|custom("a", "b")|}
    "custom";
  test_env (fresh ()) "bare unknown name fails naming the valid set"
    {|p = pipeline {
  a = node(command = 1, serializer = write_pkl, functions = ["s.py"])
}
p|}
    "Unknown strategy `write_pkl`";
  test_env (fresh ()) "bare-name error teaches the custom escape"
    {|p = pipeline {
  a = node(command = 1, serializer = write_pkl, functions = ["s.py"])
}
p|}
    "custom(\"write_pkl\")";
  test_env (fresh ()) "custom-quoted strategy constructs"
    {|p = pipeline {
  a = node(command = 1, serializer = custom("write_pkl"), functions = ["s.py"])
}
pipeline_nodes(p)|}
    "a";
  test_env (fresh ()) "built-in caret form still works"
    {|p = pipeline {
  a = node(command = 1, serializer = ^csv)
}
pipeline_nodes(p)|}
    "a";
  test_env (fresh ()) "default still works"
    {|p = pipeline {
  a = node(command = 1, serializer = default)
}
pipeline_nodes(p)|}
    "a";
  test_env (fresh ()) "variable holding a closed strategy still works"
    {|s = ^csv
p = pipeline {
  a = node(command = 1, serializer = s)
}
pipeline_nodes(p)|}
    "a";
  test_env (fresh ()) "variable holding a custom quote still works"
    {|w = custom("write_pkl")
p = pipeline {
  a = node(command = 1, serializer = w, functions = ["s.py"])
}
pipeline_nodes(p)|}
    "a";
  test_env (fresh ()) "deserializer position enforces the same rule"
    {|p = pipeline {
  a = node(command = 1, deserializer = read_pkl, functions = ["s.py"])
}
p|}
    "Unknown strategy `read_pkl`";
  test_env (fresh ()) "default sentinels validate clean"
    {|p = pipeline {
  a = node(command = 1)
}
pipeline_validate(p)|}
    "[]";
  print_newline ()
