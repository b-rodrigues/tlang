(* tests/cli/test_demo.ml *)

let run_tests pass_count fail_count _failures _eval_string _eval_string_env _test =
  Printf.printf "Demo / Tour tests:\n";
  let test_message name predicate =
    if predicate then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  ✗ %s\n" name
    end
  in

  let env = Packages.init_env () in
  let ran_cleanly =
    try
      Demo.run ~headless:true env;
      true
    with exn ->
      Printf.eprintf "Demo.run failed with: %s\n" (Printexc.to_string exn);
      false
  in
  test_message "Demo.run headless completes without errors" ran_cleanly
