open Ast
let test _name _input _expected =
  ()

let run_tests pass_count fail_count _eval_string eval_string_env _test =
  Printf.printf "ONNX Native:\n";

  (* Create a dummy ONNX file *)
  let filename = "test_dummy.onnx" in
  let out = open_out filename in
  output_string out "onnx-binary-content-mock";
  close_out out;

  (* Verify t_read_onnx loading *)
  let env = Packages.init_env () in
  let (v, _) = eval_string_env (Printf.sprintf {| t_read_onnx("%s") |} filename) env in
  (match v with
   | Ast.VDict pairs ->
       (match List.assoc_opt "model_type" pairs with
        | Some (VString "onnx") ->
            incr pass_count; Printf.printf "  ✓ t_read_onnx identifies model_type\n"
        | _ ->
            incr fail_count; Printf.printf "  ✗ t_read_onnx failed to identify model_type\n");
       (match List.assoc_opt "path" pairs with
        | Some (VString path) when path = filename ->
            incr pass_count; Printf.printf "  ✓ t_read_onnx stores path\n"
        | _ ->
            incr fail_count; Printf.printf "  ✗ t_read_onnx failed to store path")
   | _ ->
       incr fail_count; 
       Printf.printf "  ✗ t_read_onnx returned unexpected value type: %s\n" (Ast.Utils.value_to_string v));

  (* cleanup *)
  Sys.remove filename;
  print_newline ()
