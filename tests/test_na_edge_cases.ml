let capture_stderr f =
  let stderr_fd = Unix.descr_of_out_channel stderr in
  let saved_stderr = Unix.dup stderr_fd in
  let read_fd, write_fd = Unix.pipe () in
  Unix.dup2 write_fd stderr_fd;
  Unix.close write_fd;
  let restore () =
    flush stderr;
    Unix.dup2 saved_stderr stderr_fd;
    Unix.close saved_stderr
  in
  try
    let (v, env) = f () in
    restore ();
    let buffer = Buffer.create 128 in
    let chunk = Bytes.create 256 in
    let rec drain () =
      match Unix.read read_fd chunk 0 (Bytes.length chunk) with
      | 0 -> ()
      | n ->
          Buffer.add_subbytes buffer chunk 0 n;
          drain ()
    in
    drain ();
    Unix.close read_fd;
    ((v, env), Buffer.contents buffer)
  with exn ->
    restore ();
    Unix.close read_fd;
    raise exn

let run_tests pass_count fail_count _eval_string eval_string_env test =
  Printf.printf "NA Edge Cases — Strict Flag Validation:\n";
  test "abs(na_ignore = 1)" "abs(4, na_ignore = 1)" {|Error(TypeError: "Flag `na_ignore` must be Bool, but received Int.")|};
  test "mean(na_rm = \"yes\")" {|mean([1, NA], na_rm = "yes")|} {|Error(TypeError: "Flag `na_rm` must be Bool, but received String.")|};
  test "sum(na_rm = 1.0)" "sum([1], na_rm = 1.0)" {|Error(TypeError: "Flag `na_rm` must be Bool, but received Float.")|};
  test "min(na_rm = NA)" "min([1], na_rm = NA)" {|Error(TypeError: "Flag `na_rm` must be Bool, but received NA.")|};
  
  Printf.printf "NA Edge Cases — filter() Warnings:\n";
  let env_warn = Packages.init_env () in
  let show_warnings_before = !Eval.show_warnings in
  Eval.show_warnings := true;
  
  (* Row-wise filter warning *)
  (try
    let ((v_row, _), warn_row) = capture_stderr (fun () ->
      eval_string_env 
        {|df_row = dataframe([[x: 1, y: 1], [x: NA, y: 2], [x: 3, y: 3]]); filter(df_row, \(r) r.x > 1)|}
        env_warn
    ) in
    if Ast.Utils.value_to_string v_row = "DataFrame(1 rows x 2 cols: [x, y])" && 
       (try let _ = Str.search_forward (Str.regexp "warning") (String.lowercase_ascii warn_row) 0 in true with _ -> false) then begin
      incr pass_count; Printf.printf "  ✓ row-wise filter warns on NA\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ row-wise filter warns on NA\n    Result: %s\n    Warning: %s\n" (Ast.Utils.value_to_string v_row) warn_row
    end
  with e ->
    incr fail_count; Printf.printf "  ✗ row-wise filter warns on NA (EXCEPTION: %s)\n" (Printexc.to_string e));

  (* Vectorized filter compound warning *)
  (try
    let ((v_vec, _), warn_vec) = capture_stderr (fun () ->
      eval_string_env 
        {|df_vec = dataframe([[x: 1, y: 1], [x: NA, y: 2], [x: 3, y: NA]]); filter(df_vec, $x > 0 && $y > 0)|}
        env_warn
    ) in
    if Ast.Utils.value_to_string v_vec = "DataFrame(1 rows x 2 cols: [x, y])" &&
       (try let _ = Str.search_forward (Str.regexp "excluded 2 rows") (String.lowercase_ascii warn_vec) 0 in true with _ -> false) then begin
      incr pass_count; Printf.printf "  ✓ vectorized filter warns on multiple NA rows (intersected)\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ vectorized filter warns on multiple NA rows (intersected)\n    Warning: %s\n" warn_vec
    end
  with e ->
    incr fail_count; Printf.printf "  ✗ vectorized filter warns on multiple NA (EXCEPTION: %s)\n" (Printexc.to_string e));

  Eval.show_warnings := show_warnings_before;
  
  Printf.printf "NA Edge Cases — Arithmetic:\n";
  test "1 + NA" "1 + NA" {|Error(NAPredicateError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "NA - 1" "NA - 1" {|Error(NAPredicateError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "NA * NA" "NA * NA" {|Error(NAPredicateError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "Not NA" "!NA" {|Error(NAPredicateError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  
  print_newline ()
