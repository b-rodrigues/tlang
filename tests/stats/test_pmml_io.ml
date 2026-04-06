let run_tests pass_count fail_count _eval_string eval_string_env _test =
  Printf.printf "PMML IO:\n";

  let root = Test_helpers.find_repo_root () in
  let src_path = Filename.concat root "tests/golden/data/iris_random_forest.pmml" in
  let tmp_path = Filename.temp_file "tlang_pmml_" ".pmml" in
  let escaped_src = String.escaped src_path in
  let escaped_tmp = String.escaped tmp_path in
  let env = Packages.init_env () in
  let (_, env) =
    eval_string_env (Printf.sprintf {|m = t_read_pmml("%s")|} escaped_src) env
  in
  let (write_v, env) =
    eval_string_env (Printf.sprintf {|t_write_pmml(m, "%s")|} escaped_tmp) env
  in
  (match write_v with
   | Ast.VString path when path = tmp_path && Sys.file_exists tmp_path ->
       incr pass_count;
       Printf.printf "  ✓ t_write_pmml copies PMML loaded by t_read_pmml\n"
   | other ->
       incr fail_count;
       Printf.printf
         "  ✗ t_write_pmml copies PMML loaded by t_read_pmml\n    Got: %s\n"
         (Ast.Utils.value_to_string other));

  let (roundtrip_v, _) =
    eval_string_env (Printf.sprintf {|m2 = t_read_pmml("%s"); m2.model_type|} escaped_tmp) env
  in
  (match roundtrip_v with
   | Ast.VString "random_forest" ->
       incr pass_count;
       Printf.printf "  ✓ PMML pass-through artifact can be read again\n"
   | other ->
       incr fail_count;
       Printf.printf
         "  ✗ PMML pass-through artifact can be read again\n    Got: %s\n"
         (Ast.Utils.value_to_string other));

  let invalid_tmp_path = Filename.temp_file "tlang_pmml_invalid_" ".pmml" in
  let escaped_invalid_tmp = String.escaped invalid_tmp_path in
  let (invalid_v, _) =
    eval_string_env
      (Printf.sprintf {|t_write_pmml([model_type: "random_forest"], "%s")|} escaped_invalid_tmp)
      (Packages.init_env ())
  in
  (match invalid_v with
   | Ast.VError { message; _ }
     when Test_helpers.contains message "loaded via `t_read_pmml()` or `read_node()`" ->
       incr pass_count;
       Printf.printf "  ✓ t_write_pmml rejects PMML Dicts without source artifacts\n"
   | other ->
       incr fail_count;
       Printf.printf
         "  ✗ t_write_pmml rejects PMML Dicts without source artifacts\n    Got: %s\n"
         (Ast.Utils.value_to_string other));

  if Sys.file_exists tmp_path then Sys.remove tmp_path;
  if Sys.file_exists invalid_tmp_path then Sys.remove invalid_tmp_path;
  print_newline ()
