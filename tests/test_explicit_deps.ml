(* tests/test_explicit_deps.ml *)
(* Unit tests for explicit deps argument in nodes *)

let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =

  Printf.printf "Pipeline — explicit deps:\n";

  test "explicit deps with bare identifiers"
    {|p = pipeline {
  raw_data = 1
  summary_node = node(command = <{ 2 }>, deps = [raw_data])
}
pipeline_deps(p)|}
    {|{`raw_data`: [], `summary_node`: ["raw_data"]}|};

  test "explicit deps with strings"
    {|p = pipeline {
  raw_data = 1
  summary_node = node(command = <{ 2 }>, deps = ["raw_data"])
}
pipeline_deps(p)|}
    {|{`raw_data`: [], `summary_node`: ["raw_data"]}|};

  test "explicit deps with symbols (^raw_data)"
    {|p = pipeline {
  raw_data = 1
  summary_node = node(command = <{ 2 }>, deps = [^raw_data])
}
pipeline_deps(p)|}
    {|{`raw_data`: [], `summary_node`: ["raw_data"]}|};

  test "explicit deps with mixed list"
    {|p = pipeline {
  a = 1; b = 2; c = 3
  d = node(command = <{ 4 }>, deps = [a, "b", ^c])
}
pipeline_deps(p)|}
    {|{`a`: [], `b`: [], `c`: [], `d`: ["a", "b", "c"]}|};

  test "explicit deps with single identifier"
    {|p = pipeline {
  raw_data = 1
  summary_node = node(command = <{ 2 }>, deps = raw_data)
}
pipeline_deps(p)|}
    {|{`raw_data`: [], `summary_node`: ["raw_data"]}|};

  test "explicit deps override automatic detection"
    {|p = pipeline {
  a = 1
  b = 2
  c = node(command = <{ a + b }>, deps = [a])
}
pipeline_deps(p)|}
    {|{`a`: [], `b`: [], `c`: ["a"]}|};

  test "explicit deps persist through mutate_node"
    {|p = pipeline {
  a = 1
  b = node(command = <{ 2 }>, deps = [a])
}
p2 = p |> mutate_node($noop = true)
pipeline_to_frame(p2) |> filter(\(row) row.name == "b") |> \(df) get(df.deps, 0)|}
    {|"a"|};

  test "explicit deps rewired through rename_node"
    {|p = pipeline {
  a = 1
  b = node(command = <{ 2 }>, deps = [a])
}
p2 = p |> rename_node("a", "alpha")
pipeline_deps(p2)|}
    {|{`alpha`: [], `b`: ["alpha"]}|};

  print_newline ()
