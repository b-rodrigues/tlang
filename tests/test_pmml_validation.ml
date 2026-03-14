let run_tests pass_count fail_count _eval_string _eval_string_env _test =
  Printf.printf "PMML — Schema validation:\n";
  let path = Filename.temp_file "t_pmml_invalid_" ".xml" in
  let oc = open_out path in
  output_string oc "<PMML></PMML>";
  close_out oc;
  (match Pmml_utils.validate_pmml_schema path with
   | Ok () ->
       incr fail_count;
       Printf.printf "  ✗ invalid PMML unexpectedly passed schema validation\n"
   | Error _ ->
       incr pass_count;
       Printf.printf "  ✓ invalid PMML rejected by schema validation\n");
  (try Sys.remove path with _ -> ());
  print_newline ()
