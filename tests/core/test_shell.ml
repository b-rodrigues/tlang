let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Shell Escape:\n";
  test "simple echo" "?(echo hello)" "\"hello\\n\"";
  test "expression capture" "let out = ?(echo -n 'hello world'); out" "\"hello world\"";
  test "multi-line command" "?(
    echo line1
    echo line2
  )" "\"line1\\nline2\\n\"";
  test "nested parentheses" "?(echo $(echo nested))" "\"nested\\n\"";
  test "shell features - piping" "?(echo 'hello' | tr 'a-z' 'A-Z')" "\"HELLO\\n\"";
  
  (* Error cases *)
  test "non-zero exit code" "?(ls /nonexistent_path_blah_blah)" {|Error(ShellError: "ls: cannot access '/nonexistent_path_blah_blah': No such file or directory")|};
  test "command not found" "?(nosuchcommand_12345)" {|Error(ShellError: "failed to execute shell command")|};

  (* Special case: cd *)
  test "cd to home (implicit)" "?(cd)" "\"\"";
  test "cd to ~" "?(cd ~)" "\"\"";
  test "cd and check pwd" "let old = ?(pwd); ?(cd /tmp); let cur = ?(pwd); ?(cd !!old); cur" "\"/tmp\\n\"";
  test "cd error" "?(cd /nonexistent_folder_abc)" {|Error(ShellError: "No such directory: /nonexistent_folder_abc (No such file or directory)")|};

  print_newline ()
