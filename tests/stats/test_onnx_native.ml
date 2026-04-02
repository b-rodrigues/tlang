open Ast

let run_tests pass_count fail_count _eval_string eval_string_env _test =
  Printf.printf "ONNX Native:\n";

  (* Create a dummy ONNX file *)
  let filename = Filename.temp_file "onnx_test" ".onnx" in
  
  Fun.protect (fun () ->
    let out = open_out filename in
    output_string out "onnx-binary-content-mock";
    close_out out;

    (* Verify t_read_onnx loading *)
    let env = Packages.init_env () in
    let (v, _) = eval_string_env (Printf.sprintf {| t_read_onnx("%s") |} filename) env in
    (match v with
     | Ast.VDict pairs ->
         (match List.assoc_opt "model_type" pairs with
          | Some (VSymbol "^onnx") ->
              incr pass_count; Printf.printf "  ✓ t_read_onnx identifies model_type\n"
          | _ ->
              incr fail_count; Printf.printf "  ✗ t_read_onnx failed to identify model_type (got: %s)\n" (Ast.Utils.value_to_string v));
         (match List.assoc_opt "path" pairs with
          | Some (VString path) when path = filename ->
              incr pass_count; Printf.printf "  ✓ t_read_onnx stores path\n"
          | _ ->
              incr fail_count; Printf.printf "  ✗ t_read_onnx failed to store path");
         
         (* Verify predict call on invalid ONNX fails gracefully *)
         (* Use valid dataframe construction: list of rows/dicts using [...] syntax *)
         let (v_pred, _) = eval_string_env (Printf.sprintf {| 
           df = dataframe([ [n1: 1.0, n2: 3.0], [n1: 2.0, n2: 4.0] ]);
           model = t_read_onnx("%s");
           predict(df, model)
         |} filename) env in
         (match v_pred with
          | Ast.VError { code = (RuntimeError | FileError); _ } ->
              (* It could fail on file content or on predict execution *)
              incr pass_count; Printf.printf "  ✓ predict on invalid ONNX fails gracefully\n"
          | _ ->
              incr fail_count; 
              Printf.printf "  ✗ predict on invalid ONNX should return error, got: %s\n" (Ast.Utils.value_to_string v_pred))
     | _ ->
         incr fail_count; 
         Printf.printf "  ✗ t_read_onnx returned unexpected value type: %s\n" (Ast.Utils.value_to_string v))
  ) ~finally:(fun () ->
    if Sys.file_exists filename then Sys.remove filename
  );
  
  print_newline ()
