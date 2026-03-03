let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Shell Escape:\n";
  let old_cwd = Sys.getcwd () in

  (* Basic output capture: ShellResult displays as quoted stdout string *)
  test "simple echo" "out = ?<{echo hello}>; out" "\"hello\\n\"";
  test "expression capture" "out = ?<{echo -n 'hello world'}>; out" "\"hello world\"";
  test "multi-line command"
    "out = ?<{\n    echo line1\n    echo line2\n  }>; out"
    "\"line1\\nline2\\n\"";
  test "nested parentheses" "out = ?<{echo $(echo nested)}>; out" "\"nested\\n\"";
  test "shell features - piping" "out = ?<{echo 'hello' | tr 'a-z' 'A-Z'}>; out" "\"HELLO\\n\"";

  (* Structured access: .stdout, .stderr, .exit_code *)
  test "stdout field" "?<{echo hello}>.stdout" "\"hello\\n\"";
  test "exit_code success" "?<{echo ok}>.exit_code" "0";
  test "exit_code failure" "?<{ls /nonexistent_path_blah_blah}>.exit_code" "2";
  test "stderr non-empty on error"
    "contains(?<{ls /nonexistent_path_blah_blah}>.stderr, \"No such file or directory\")"
    "true";
  test "type is ShellResult" "type(?<{echo hi}>)" "\"ShellResult\"";

  (* A failing command no longer raises a VError — check exit_code instead *)
  test "command not found exit_code"
    "?<{nosuchcommand_12345}>.exit_code"
    "127";

  (* Special case: cd *)
  test "cd to /tmp returns empty stdout" "?<{cd /tmp}>.stdout" "\"\"";
  test "cd exit_code success" "?<{cd /tmp}>.exit_code" "0";
  test "cd back" (Printf.sprintf "?<{cd %s}>.exit_code" old_cwd) "0";
  test "cd to home (implicit)" "?<{cd}>.exit_code" "0";
  test "cd to ~" "?<{cd ~}>.exit_code" "0";
  test "cd error exit_code" "?<{cd /nonexistent_folder_abc}>.exit_code" "1";
  test "cd error stderr contains path"
    "contains(?<{cd /nonexistent_folder_abc}>.stderr, \"/nonexistent_folder_abc\")"
    "true";

  (* strsplit integration *)
  test "strsplit with newline"
    "lines = strsplit(?<{printf \"a\\nb\\nc\"}>  , \"\\n\"); length(lines)"
    "3";

  (* Restore CWD *)
  Sys.chdir old_cwd;
  print_newline ()
