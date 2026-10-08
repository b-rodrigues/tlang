(* tests/pipeline/test_strategy_closed.ml *)
(* Closed serializer/deserializer strategies (spec path item 2).
   Only built-ins (`default`, `^csv`, ...) and strategy dicts
   ([format: ^name, ...snippets]) are strategies. Bare names fail where
   a strategy is expected; there is no quoting escape. Fresh environment
   per test so nothing leaks across cases. *)

let run_tests pass_count fail_count _failures _eval_string _eval_string_env test test_env _test_equal =
  Printf.printf "Closed strategies:\n";
  let fresh () = Packages.init_env () in
  test "strategy baseline arithmetic"
    "1 + 2"
    "3";
  test_env (fresh ()) "custom quoting is gone"
    {|custom("write_pkl")|}
    "not defined";
  test_env (fresh ()) "bare unknown name fails naming the dict form"
    {|p = pipeline {
  a = node(command = 1, serializer = write_pkl, functions = ["s.py"])
}
p|}
    "strategy dict";
  test_env (fresh ()) "bare-name error names the valid set"
    {|p = pipeline {
  a = node(command = 1, serializer = write_pkl, functions = ["s.py"])
}
p|}
    "Valid built-in formats";
  test_env (fresh ()) "strategy dict constructs"
    {|p = pipeline {
  a = node(command = 1, serializer = [format: ^yml, r_writer: <{ function(obj, path) write.csv(obj, path) }>, r_reader: <{ function(path) read.csv(path) }>])
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
  test_env (fresh ()) "variable holding a strategy dict still works"
    {|w = [format: ^yml, r_writer: <{ function(obj, path) write.csv(obj, path) }>]
p = pipeline {
  a = node(command = 1, serializer = w)
}
pipeline_nodes(p)|}
    "a";
  test_env (fresh ()) "deserializer position enforces the same rule"
    {|p = pipeline {
  a = node(command = 1, deserializer = read_pkl, functions = ["s.py"])
}
p|}
    "strategy dict";
  test_env (fresh ()) "snippet-only dict without deps suggests the format key"
    {|p = pipeline {
  a = node(command = 1, serializer = [r_writer: <{ function(obj, path) write.csv(obj, path) }>])
}
pipeline_validate(p)|}
    "missing its `format` key";
  test_env (fresh ()) "strategy dict with unknown key fails validation"
    {|p = pipeline {
  a = node(command = 1, serializer = [format: ^yml, frog: 1])
}
pipeline_validate(p)|}
    "frog";
  test_env (fresh ()) "per-dependency map for nodes named reader/writer validates"
    {|p = pipeline {
  reader = node(command = 1)
  writer = node(command = 2)
  out = rn(command = <{ reader + writer }>, deserializer = [reader: ^csv, writer: ^json])
}
pipeline_validate(p)|}
    "[]";
  test_env (fresh ()) "per-dependency map with typo key names valid deps"
    {|p = pipeline {
  reader = node(command = 1)
  out = rn(command = <{ reader + 1 }>, deserializer = [reder: ^csv])
}
pipeline_validate(p)|}
    "Unknown dependency `reder`";
  test_env (fresh ()) "dependency literally named format names the ambiguity"
    {|p = pipeline {
  format = node(command = 1)
  other = node(command = 2)
  out = rn(command = <{ format + other }>, deserializer = [format: ^csv, other: ^json])
}
pipeline_validate(p)|}
    "cannot be keyed in map form";
  test_env (fresh ()) "custom format without runtime snippet fails validation"
    {|p = pipeline {
  a = rn(command = <{ 1 }>, serializer = [format: ^yml])
}
pipeline_validate(p)|}
    "r_writer";
  test_env (fresh ()) "custom format on T fails validation"
    {|p = pipeline {
  a = node(command = 1, serializer = [format: ^yml, r_writer: <{ function(obj, path) write.csv(obj, path) }>])
}
pipeline_validate(p)|}
    "built-in formats only";
  test_env (fresh ()) "custom format on sh fails validation"
    {|p = pipeline {
  s = shn(command = <{ echo hi }>, serializer = [format: ^yml, r_writer: <{ function(obj, path) write.csv(obj, path) }>])
}
pipeline_validate(p)|}
    "not supported for runtime";
  test_env (fresh ()) "quarto serializer is undefined"
    {|p = pipeline {
  r = qn(script = "report.qmd", serializer = ^csv)
}
pipeline_validate(p)|}
    "serializer for quarto undefined";
  test_env (fresh ()) "quarto deserializer is undefined"
    {|p = pipeline {
  r = qn(script = "report.qmd", deserializer = ^csv)
}
pipeline_validate(p)|}
    "deserializer for quarto undefined";
  test_env (fresh ()) "mutate_node rejects string strategies"
    {|p = pipeline { a = node(command = 1) }
p |> mutate_node($serializer = "csv")|}
    "expects a Strategy";
  test_env (fresh ()) "global options reject string strategies"
    {|p = pipeline { a = node(command = 1) }
set_pipeline_global_options(p, serializer = "csv")|}
    "expects a Strategy";
  test_env (fresh ()) "text on R fails validation"
    {|p = pipeline {
  a = rn(command = <{ 1 }>, serializer = ^text)
}
pipeline_validate(p)|}
    "only supported for T and sh";
  test_env (fresh ()) "text deserializer on R fails validation"
    {|p = pipeline {
  a = rn(command = <{ 1 }>)
  b = rn(command = <{ a }>, deserializer = ^text)
}
pipeline_validate(p)|}
    "only supported for T and sh";
  test_env (fresh ()) "text on T validates clean"
    {|p = pipeline {
  a = node(command = 1, serializer = ^text)
}
pipeline_validate(p)|}
    "[]";
  test_env (fresh ()) "tlang validates clean"
    {|p = pipeline {
  a = node(command = 1, serializer = ^tlang)
}
pipeline_validate(p)|}
    "[]";
  test_env (fresh ()) "default sentinels validate clean"
    {|p = pipeline {
  a = node(command = 1)
}
pipeline_validate(p)|}
    "[]";
  (* Table-driven agreement: every known format validates on exactly the
     runtimes whose emitter table maps it (minus fetchurl-only ^bin), so
     validation and emission cannot drift apart into a user-reachable
     "Internal error". *)
  (let open Ast in
   let ctors = [
     ("T", (fun s -> Printf.sprintf "node(command = 1, serializer = %s)" s));
     ("R", (fun s -> Printf.sprintf "rn(command = <{ 1 }>, serializer = %s)" s));
     ("Python", (fun s -> Printf.sprintf "pyn(command = <{ 1 }>, serializer = %s)" s));
     ("Julia", (fun s -> Printf.sprintf "jln(command = <{ 1 }>, serializer = %s)" s));
   ] in
   let formats = Pipeline_validation.known_serializer_formats in
   List.iter (fun (rt, ctor) ->
     let mapped = Nix_emit_node.mapped_formats_for_runtime rt in
     List.iter (fun fmt ->
       let arg = if fmt = "default" then "default" else "^" ^ fmt in
       let code = Printf.sprintf "p = pipeline { a = %s }\npipeline_validate(p)" (ctor arg) in
       let (v, _) = _eval_string_env code (Packages.init_env ()) in
       let expect_clean = List.mem fmt mapped && fmt <> "bin" in
       let is_clean = match v with VList [] -> true | _ -> false in
       if is_clean = expect_clean then
         (incr pass_count;
          Printf.printf "  SUCCESS table: ^%s on %s %s\n" fmt rt (if expect_clean then "validates" else "rejected"))
       else
         (incr fail_count;
          Printf.printf "  FAILURE table: ^%s on %s expected %s, got %s\n" fmt rt
            (if expect_clean then "clean" else "error") (Ast.Utils.value_to_string v))
     ) formats
   ) ctors);
  print_newline ()
