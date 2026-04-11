(* tests/test_explicit_deps.ml *)
(* Unit tests for explicit deps argument in nodes *)

let run_tests pass_count fail_count _eval_string eval_string_env test =
  ignore test;

  Printf.printf "Pipeline — explicit deps:\n";

  (* Basic usage with bare identifiers *)
  let env = Packages.init_env () in
  let (v, _) = eval_string_env
    {|p = pipeline {
  raw_data = 1
  summary = node(command = <{ 2 }>, deps = [raw_data])
}
pipeline_deps(p)|}
    env in
  let result = Ast.Utils.value_to_string v in
  if result = {|{`raw_data`: [], `summary`: ["raw_data"]}|} then begin
    incr pass_count; Printf.printf "  ✓ explicit deps with bare identifiers\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ explicit deps with bare identifiers\n    Expected: {`raw_data`: [], `summary`: [\"raw_data\"]}\n    Got: %s\n" result
  end;

  (* Explicit deps with strings *)
  let (v, _) = eval_string_env
    {|p = pipeline {
  raw_data = 1
  summary = node(command = <{ 2 }>, deps = ["raw_data"])
}
pipeline_deps(p)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|{`raw_data`: [], `summary`: ["raw_data"]}|} then begin
    incr pass_count; Printf.printf "  ✓ explicit deps with strings\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ explicit deps with strings\n    Expected: {`raw_data`: [], `summary`: [\"raw_data\"]}\n    Got: %s\n" result
  end;

  (* Explicit deps with symbols (with ^) *)
  let (v, _) = eval_string_env
    {|p = pipeline {
  raw_data = 1
  summary = node(command = <{ 2 }>, deps = [^raw_data])
}
pipeline_deps(p)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|{`raw_data`: [], `summary`: ["raw_data"]}|} then begin
    incr pass_count; Printf.printf "  ✓ explicit deps with symbols (^raw_data)\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ explicit deps with symbols\n    Expected: {`raw_data`: [], `summary`: [\"raw_data\"]}\n    Got: %s\n" result
  end;

  (* Mixed list *)
  let (v, _) = eval_string_env
    {|p = pipeline {
  a = 1; b = 2; c = 3
  d = node(command = <{ 4 }>, deps = [a, "b", ^c])
}
pipeline_deps(p)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|{`a`: [], `b`: [], `c`: [], `d`: ["a", "b", "c"]}|} then begin
    incr pass_count; Printf.printf "  ✓ explicit deps with mixed list\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ explicit deps with mixed list\n    Expected: {`a`: [], `b`: [], `c`: [], `d`: [\"a\", \"b\", \"c\"]}\n    Got: %s\n" result
  end;

  (* Single identifier (not in list) *)
  let (v, _) = eval_string_env
    {|p = pipeline {
  raw_data = 1
  summary = node(command = <{ 2 }>, deps = raw_data)
}
pipeline_deps(p)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|{`raw_data`: [], `summary`: ["raw_data"]}|} then begin
    incr pass_count; Printf.printf "  ✓ explicit deps with single identifier\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ explicit deps with single identifier\n    Expected: {`raw_data`: [], `summary`: [\"raw_data\"]}\n    Got: %s\n" result
  end;

  (* Explicit deps override automatic detection *)
  let (v, _) = eval_string_env
    {|p = pipeline {
  a = 1
  b = 2
  c = node(command = <{ a + b }>, deps = [a])
}
pipeline_deps(p)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|{`a`: [], `b`: [], `c`: ["a"]}|} then begin
    incr pass_count; Printf.printf "  ✓ explicit deps override automatic detection\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ explicit deps override\n    Expected: {`a`: [], `b`: [], `c`: [\"a\"]}\n    Got: %s\n" result
  end;

  (* Persistence through mutate_node *)
  let (v, _) = eval_string_env
    {|p = pipeline {
  a = 1
  b = node(command = <{ 2 }>, deps = [a])
}
p2 = p |> mutate_node($noop = true)
pipeline_to_frame(p2) |> filter(\(row) row.name == "b") |> \(df) get(df.deps, 0)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|"a"|} then begin
    incr pass_count; Printf.printf "  ✓ explicit deps persist through mutate_node\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ explicit deps persistence (mutate_node)\n    Expected: \"a\"\n    Got: %s\n" result
  end;

  (* Persistence through rename_node *)
  let (v, _) = eval_string_env
    {|p = pipeline {
  a = 1
  b = node(command = <{ 2 }>, deps = [a])
}
p2 = p |> rename_node("a", "alpha")
pipeline_deps(p2)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|{`alpha`: [], `b`: ["alpha"]}|} then begin
    incr pass_count; Printf.printf "  ✓ explicit deps rewired through rename_node\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ explicit deps rewire (rename_node)\n    Expected: {`alpha`: [], `b`: [\"alpha\"]}\n    Got: %s\n" result
  end;

  print_newline ()
