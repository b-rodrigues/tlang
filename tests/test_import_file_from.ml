(* tests/test_import_file_from.ml *)
(* Unit tests for the ImportFileFrom feature: import "file.t"[name] *)

let run_tests _pass_count _fail_count _failures _eval_string eval_string_env test test_env =

  Printf.printf "ImportFileFrom — Basic selective import:\n";

  (* Write a temporary T file that defines two names *)
  let tmp_file = Filename.temp_file "t_import_test" ".t" in
  (let oc = open_out tmp_file in
   output_string oc "foo = 42\nbar = 99\n";
   close_out oc);

  test "single name imported correctly"
    (Printf.sprintf {|import "%s"[foo]; foo|} tmp_file)
    "42";

  (* The non-imported name should not be in scope *)
  let env = Packages.init_env () in
  let env2 = Test_helpers.eval_setup eval_string_env env "test_import_file_from:20" (Printf.sprintf {|import "%s"[foo]|} tmp_file) in
  test_env env2 "non-imported name is not in scope"
    "bar"
    "Error";

  test "multiple names imported correctly"
    (Printf.sprintf {|import "%s"[foo, bar]; foo + bar|} tmp_file)
    "141";

  print_newline ();

  Printf.printf "ImportFileFrom — Alias support:\n";

  test "aliased import bound under alias name"
    (Printf.sprintf {|import "%s"[myalias=foo]; myalias|} tmp_file)
    "42";

  (* The original name should not be bound when an alias is used *)
  let env_alias = Packages.init_env () in
  let env_alias2 = Test_helpers.eval_setup eval_string_env env_alias "test_import_file_from:41" (Printf.sprintf {|import "%s"[myalias=foo]|} tmp_file) in
  test_env env_alias2 "original name not in scope when alias used"
    "foo"
    "Error";

  print_newline ();

  Printf.printf "ImportFileFrom — Error handling:\n";

  test "missing name returns error"
    (Printf.sprintf {|import "%s"[nonexistent]|} tmp_file)
    "Error";

  test "missing file returns error"
    {|import "/nonexistent/path/file.t"[foo]|}
    "Error";

  (* Syntax error in imported file returns parse error *)
  let bad_file = Filename.temp_file "t_import_bad" ".t" in
  (let oc = open_out bad_file in
   output_string oc "this is not valid T @@@ syntax!!!\n";
   close_out oc);
  test "parse error in imported file returns error"
    (Printf.sprintf {|import "%s"[foo]|} bad_file)
    "Error";

  (* Clean up temporary files *)
  (try Sys.remove tmp_file with _ -> ());
  (try Sys.remove bad_file with _ -> ());

  print_newline ()
