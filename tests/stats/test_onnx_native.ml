

let run_tests pass_count fail_count _eval_string eval_string_env _test =
  Printf.printf "ONNX Native:\n";

  (* Create a dummy ONNX file *)
  let filename = Filename.temp_file "onnx_test" ".onnx" in
  
  Fun.protect (fun () ->
    let out = open_out filename in
    output_string out "onnx-binary-content-mock";
    close_out out;

    (* Verify t_read_onnx loading fails gracefully on mock file *)
    let env = Packages.init_env () in
    let (v, _) = eval_string_env (Printf.sprintf {| t_read_onnx("%s") |} filename) env in
    (match v with
     | Ast.VError _ ->
         incr pass_count; Printf.printf "  ✓ t_read_onnx returns error for invalid model content\n"
     | _ ->
         incr fail_count; 
         Printf.printf "  ✗ t_read_onnx should have returned VError for mock content, got: %s\n" (Ast.Utils.value_to_string v))
  ) ~finally:(fun () ->
    if Sys.file_exists filename then Sys.remove filename
  );
  
  print_newline ()
