let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Shell Escape:\n";
  test "simple echo" "out = ?<{echo hello}>; out" "\"hello\\n\"";
  test "expression capture" "out = ?<{echo -n 'hello world'}>; out" "\"hello world\"";
  test "multi-line command"
    "out = ?<{\n    echo line1\n    echo line2\n  }>; out"
    "\"line1\\nline2\\n\"";
  test "nested parentheses" "out = ?<{echo $(echo nested)}>; out" "\"nested\\n\"";
  test "shell features - piping" "out = ?<{echo 'hello' | tr 'a-z' 'A-Z'}>; out" "\"HELLO\\n\"";

  (* Error cases — use error_code/error_message to avoid brittle platform-specific strings *)
  test "non-zero exit code error_code"
    "res = ?<{ls /nonexistent_path_blah_blah}>; error_code(res)"
    "\"ShellError\"";
  test "non-zero exit code contains message"
    "res = ?<{ls /nonexistent_path_blah_blah}>; contains(error_message(res), \"No such file or directory\")"
    "true";
  test "command not found error_code"
    "res = ?<{nosuchcommand_12345}>; error_code(res)"
    "\"ShellError\"";

  (* Special case: cd *)
  test "cd to home (implicit)" "out = ?<{cd}>; out" "\"\"";
  test "cd to ~" "out = ?<{cd ~}>; out" "\"\"";
  test "cd error error_code"
    "res = ?<{cd /nonexistent_folder_abc}>; error_code(res)"
    "\"ShellError\"";
  test "cd error contains path"
    "res = ?<{cd /nonexistent_folder_abc}>; contains(error_message(res), \"/nonexistent_folder_abc\")"
    "true";

  print_newline ()
