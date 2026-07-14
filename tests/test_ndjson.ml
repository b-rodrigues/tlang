(* tests/test_ndjson.ml *)
(* Tests for src/pipeline/ndjson_stream.ml — NDJSON streaming events *)

let run_tests pass_count fail_count failures _eval_string _eval_string_env _test =
  Printf.printf "\n=== NDJSON stream tests ===\n\n";

  let check name condition =
    if condition then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  ✗ %s\n" name in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in

  Printf.printf "seq counter:\n";
  Ndjson_stream.reset ();
  let s1 = Ndjson_stream.next_seq () in
  let s2 = Ndjson_stream.next_seq () in
  let s3 = Ndjson_stream.next_seq () in
  check "next_seq returns 1 on first call" (s1 = 1);
  check "next_seq returns 2 on second call" (s2 = 2);
  check "next_seq is monotonically increasing" (s3 > s2);

  Printf.printf "\ntruncate_tail:\n";
  let short = "line1\nline2\nline3" in
  let result_short = Ndjson_stream.truncate_tail ~max_lines:5 short in
  check "truncate_tail leaves short strings unchanged" (result_short = short);
  let many_lines = String.concat "\n" (List.init 100 (fun i -> Printf.sprintf "line_%d" i)) in
  let result_trunc = Ndjson_stream.truncate_tail ~max_lines:3 many_lines in
  let trunc_lines = String.split_on_char '\n' result_trunc in
  check "truncate_tail returns at most max_lines lines" (List.length trunc_lines = 3);
  check "truncate_tail keeps the last lines" (
    List.nth trunc_lines 0 = "line_97" &&
    List.nth trunc_lines 1 = "line_98" &&
    List.nth trunc_lines 2 = "line_99"
  );

  Printf.printf "\niso8601_timestamp:\n";
  let ts = Ndjson_stream.iso8601_timestamp () in
  check "timestamp starts with 4-digit year" (String.length ts >= 4);
  check "timestamp contains T separator" (
    try let _ = Str.search_forward (Str.regexp "T") ts 0 in true
    with Not_found -> false
  );
  check "timestamp ends with Z" (ts.[String.length ts - 1] = 'Z');

  Printf.printf "\nlog_path_for_node:\n";
  let lp = Ndjson_stream.log_path_for_node "my_node" in
  check "log path contains node name" (lp = "_pipeline/logs/my_node.log");

  Printf.printf "\nensure_build_logs_dir:\n";
  let dir = Ndjson_stream.ensure_build_logs_dir () in
  check "logs dir is _pipeline/logs" (dir = "_pipeline/logs");
  check "logs dir exists" (Sys.file_exists dir);

  Printf.printf "\nnode_spec type:\n";
  let ns = { Ndjson_stream.ns_id = "test_node"; ns_lang = "r"; ns_deps = ["dep1"; "dep2"] } in
  check "node_spec id matches" (ns.Ndjson_stream.ns_id = "test_node");
  check "node_spec lang matches" (ns.Ndjson_stream.ns_lang = "r");
  check "node_spec deps has 2 entries" (List.length ns.Ndjson_stream.ns_deps = 2);

  (* Helper: capture stdout to a temp file, emit, restore, then read *)
  let with_captured_stdout f =
    let tmp_path = Filename.temp_file "ndjson_test" ".out" in
    let oc = open_out tmp_path in
    let fd = Unix.descr_of_out_channel oc in
    let old_stdout_fd = Unix.dup (Unix.descr_of_out_channel stdout) in
    Unix.dup2 fd Unix.stdout;
    (try f () with e ->
       Printf.printf "  Exception: %s\n" (Printexc.to_string e));
    flush stdout;
    Unix.dup2 old_stdout_fd Unix.stdout;
    Unix.close old_stdout_fd;
    close_out oc;
    let ic = open_in tmp_path in
    let n = in_channel_length ic in
    let buf = Bytes.create n in
    really_input ic buf 0 n;
    close_in ic;
    Sys.remove tmp_path;
    Bytes.to_string buf
  in

  Printf.printf "\nemit helpers:\n";
  let output = with_captured_stdout (fun () ->
    Ndjson_stream.reset ();
    Ndjson_stream.emit_run_started ~pipeline_name:"test_project" ~nodes:[] ()
  ) in
  check "emit_run_started produces output" (String.length output > 0);
  check "output contains run_started event" (
    try let _ = Str.search_forward (Str.regexp "run_started") output 0 in true
    with Not_found -> false
  );
  check "output contains project name" (
    try let _ = Str.search_forward (Str.regexp "test_project") output 0 in true
    with Not_found -> false
  );
  check "output contains schema_version" (
    try let _ = Str.search_forward (Str.regexp "schema_version") output 0 in true
    with Not_found -> false
  );

  Printf.printf "\nemit_node_failed:\n";
  let output_failed = with_captured_stdout (fun () ->
    Ndjson_stream.reset ();
    Ndjson_stream.emit_node_failed
      ~node_id:"my_node" ~lang:"python"
      ~duration_ms:1500.0
      ~error_class:"runtime_error"
      ~message:"ImportError: no module named 'foo'"
      ~log_available:true
      ~log_path:"_pipeline/logs/my_node.log"
      ~log_tail:"error: build failed"
  ) in
  check "emit_node_failed produces output" (String.length output_failed > 0);
  check "output contains node_failed event" (
    try let _ = Str.search_forward (Str.regexp "node_failed") output_failed 0 in true
    with Not_found -> false
  );
  check "output contains node id" (
    try let _ = Str.search_forward (Str.regexp "my_node") output_failed 0 in true
    with Not_found -> false
  );
  check "output contains error_class" (
    try let _ = Str.search_forward (Str.regexp "runtime_error") output_failed 0 in true
    with Not_found -> false
  );
  check "output contains log tail" (
    try let _ = Str.search_forward (Str.regexp "build failed") output_failed 0 in true
    with Not_found -> false
  );
  check "output contains duration_ms" (
    try let _ = Str.search_forward (Str.regexp "1500") output_failed 0 in true
    with Not_found -> false
  );

  Printf.printf "\nemit_node_skipped:\n";
  let output_skipped = with_captured_stdout (fun () ->
    Ndjson_stream.reset ();
    Ndjson_stream.emit_node_skipped ~node_id:"downstream" ~caused_by:["failed_up"]
  ) in
  check "emit_node_skipped produces output" (String.length output_skipped > 0);
  check "output contains node_skipped event" (
    try let _ = Str.search_forward (Str.regexp "node_skipped") output_skipped 0 in true
    with Not_found -> false
  );
  check "output contains caused_by" (
    try let _ = Str.search_forward (Str.regexp "failed_up") output_skipped 0 in true
    with Not_found -> false
  );

  Printf.printf "\nemit_run_finished:\n";
  let output_finished = with_captured_stdout (fun () ->
    Ndjson_stream.reset ();
    Ndjson_stream.emit_run_finished
      ~status:"failed" ~total:5 ~succeeded:2 ~cached:1
      ~failed:1 ~skipped_upstream:1 ~root_causes:["bad_node"]
  ) in
  check "emit_run_finished produces output" (String.length output_finished > 0);
  check "output contains run_finished event" (
    try let _ = Str.search_forward (Str.regexp "run_finished") output_finished 0 in true
    with Not_found -> false
  );
  check "output contains status failed" (
    try let _ = Str.search_forward (Str.regexp "\"failed\"") output_finished 0 in true
    with Not_found -> false
  );
  check "output contains root_causes" (
    try let _ = Str.search_forward (Str.regexp "bad_node") output_finished 0 in true
    with Not_found -> false
  );
  check "output contains summary total 5" (
    try let _ = Str.search_forward (Str.regexp "\"total\":\\s*5") output_finished 0 in true
    with Not_found -> false
  )
