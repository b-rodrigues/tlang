(* tests/test_import_file_from.ml *)
(* Unit tests for the ImportFileFrom feature: import "file.t"[name] *)

let run_tests pass_count fail_count _eval_string eval_string_env _test =

  Printf.printf "ImportFileFrom — Basic selective import:\n";

  (* Write a temporary T file that defines two names *)
  let tmp_file = Filename.temp_file "t_import_test" ".t" in
  (let oc = open_out tmp_file in
   output_string oc "foo = 42\nbar = 99\n";
   close_out oc);

  (* Import one name from the file *)
  let env = Packages.init_env () in
  let (v, env2) = eval_string_env
    (Printf.sprintf {|import "%s"[foo]; foo|} tmp_file)
    env in
  let result = Ast.Utils.value_to_string v in
  if result = "42" then begin
    incr pass_count;
    Printf.printf "  ✓ single name imported correctly\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ single name imported correctly\n    Expected: 42\n    Got: %s\n" result
  end;

  (* The non-imported name should not be in scope *)
  let (v2, _) = eval_string_env "bar" env2 in
  let r2 = Ast.Utils.value_to_string v2 in
  if String.length r2 >= 5 && String.sub r2 0 5 = "Error" then begin
    incr pass_count;
    Printf.printf "  ✓ non-imported name is not in scope\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ non-imported name is not in scope\n    Expected: Error(...)\n    Got: %s\n" r2
  end;

  (* Import multiple names at once *)
  let (v3, _) = eval_string_env
    (Printf.sprintf {|import "%s"[foo, bar]; foo + bar|} tmp_file)
    (Packages.init_env ()) in
  let r3 = Ast.Utils.value_to_string v3 in
  if r3 = "141" then begin
    incr pass_count;
    Printf.printf "  ✓ multiple names imported correctly\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ multiple names imported correctly\n    Expected: 141\n    Got: %s\n" r3
  end;

  print_newline ();

  Printf.printf "ImportFileFrom — Alias support:\n";

  (* Import with alias: import "file.t"[myalias=foo] *)
  let (v4, _) = eval_string_env
    (Printf.sprintf {|import "%s"[myalias=foo]; myalias|} tmp_file)
    (Packages.init_env ()) in
  let r4 = Ast.Utils.value_to_string v4 in
  if r4 = "42" then begin
    incr pass_count;
    Printf.printf "  ✓ aliased import bound under alias name\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ aliased import bound under alias name\n    Expected: 42\n    Got: %s\n" r4
  end;

  (* The original name should not be bound when an alias is used *)
  let (_v5, env5) = eval_string_env
    (Printf.sprintf {|import "%s"[myalias=foo]|} tmp_file)
    (Packages.init_env ()) in
  let (v5b, _) = eval_string_env "foo" env5 in
  let r5b = Ast.Utils.value_to_string v5b in
  if String.length r5b >= 5 && String.sub r5b 0 5 = "Error" then begin
    incr pass_count;
    Printf.printf "  ✓ original name not in scope when alias used\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ original name not in scope when alias used\n    Expected: Error(...)\n    Got: %s\n" r5b
  end;

  print_newline ();

  Printf.printf "ImportFileFrom — Error handling:\n";

  (* Missing name in file returns NameError *)
  let (v6, _) = eval_string_env
    (Printf.sprintf {|import "%s"[nonexistent]|} tmp_file)
    (Packages.init_env ()) in
  let r6 = Ast.Utils.value_to_string v6 in
  if String.length r6 >= 5 && String.sub r6 0 5 = "Error" then begin
    incr pass_count;
    Printf.printf "  ✓ missing name returns error\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ missing name returns error\n    Expected: Error(...)\n    Got: %s\n" r6
  end;

  (* Missing file returns FileError *)
  let (v7, _) = eval_string_env
    {|import "/nonexistent/path/file.t"[foo]|}
    (Packages.init_env ()) in
  let r7 = Ast.Utils.value_to_string v7 in
  if String.length r7 >= 5 && String.sub r7 0 5 = "Error" then begin
    incr pass_count;
    Printf.printf "  ✓ missing file returns error\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ missing file returns error\n    Expected: Error(...)\n    Got: %s\n" r7
  end;

  (* Syntax error in imported file returns parse error *)
  let bad_file = Filename.temp_file "t_import_bad" ".t" in
  (let oc = open_out bad_file in
   output_string oc "this is not valid T @@@ syntax!!!\n";
   close_out oc);
  let (v8, _) = eval_string_env
    (Printf.sprintf {|import "%s"[foo]|} bad_file)
    (Packages.init_env ()) in
  let r8 = Ast.Utils.value_to_string v8 in
  if String.length r8 >= 5 && String.sub r8 0 5 = "Error" then begin
    incr pass_count;
    Printf.printf "  ✓ parse error in imported file returns error\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ parse error in imported file returns error\n    Expected: Error(...)\n    Got: %s\n" r8
  end;

  (* Clean up temporary files *)
  (try Sys.remove tmp_file with _ -> ());
  (try Sys.remove bad_file with _ -> ());

  print_newline ()
