(* tests/diff/test_builder_diff.ml *)
(* Tests for builder_diff: per-node hash comparison between builds *)

let run_tests pass_count fail_count failures _eval_string _eval_string_env _test =
  Printf.printf "=== Builder_diff tests ===\n\n";
  let check name condition =
    if condition then begin
      incr pass_count;
      Printf.printf "  \xe2\x9c\x93 %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  \xe2\x9c\x97 %s\n" name in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in
  let check_eq name got expected =
    if got = expected then begin
      incr pass_count;
      Printf.printf "  \xe2\x9c\x93 %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  \xe2\x9c\x97 %s\n    Expected: %s\n    Got: %s\n" name expected got in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in

  Printf.printf "Builder_diff — compute_diff:\n";

  let rec remove_path path =
    if Sys.file_exists path then
      if Sys.is_directory path then begin
        Sys.readdir path
        |> Array.iter (fun name -> remove_path (Filename.concat path name));
        Unix.rmdir path
      end else
        Sys.remove path
  in
  let make_temp_dir () =
    let candidate =
      Filename.concat
        (Filename.get_temp_dir_name ())
        (Printf.sprintf "tlang-bdiff-test-%d-%06d" (Unix.getpid ()) (Random.int 1_000_000))
    in
    Unix.mkdir candidate 0o755;
    candidate
  in

  let write_file path content =
    let oc = open_out path in
    output_string oc content;
    close_out oc
  in

  (* Test 1: identical builds -> all unchanged *)
  let dir1 = make_temp_dir () in
  let log_a1 = Filename.concat dir1 "build_log_20260101_120000_aaa.json" in
  let log_b1 = Filename.concat dir1 "build_log_20260101_130000_bbb.json" in
  let same_log = {|{
    "timestamp": "20260101_120000",
    "hash": "aaa111",
    "out_path": "/nix/store/aaa111-pipeline_output",
    "duration": 1.5,
    "pipeline": "test_pipeline",
    "nodes": [
      {"node": "read_data", "path": "/nix/store/aaa111-pipeline_output/read_data/artifact", "hash": "aaa111", "runtime": "T", "serializer": "default", "class": "VDataFrame", "dependencies": [], "status": "Completed", "success": true, "warnings": false, "duration": 0.5},
      {"node": "clean", "path": "/nix/store/bbb222-pipeline_output/clean/artifact", "hash": "bbb222", "runtime": "T", "serializer": "default", "class": "VDataFrame", "dependencies": ["read_data"], "status": "Completed", "success": true, "warnings": false, "duration": 0.3}
    ]
  }|} in
  write_file log_a1 same_log;
  write_file log_b1 same_log;
  (match Builder_diff.compute_diff log_a1 log_b1 with
   | Error msg ->
       Printf.printf "  \xe2\x9c\x97 identical builds: %s\n" msg;
       incr fail_count
   | Ok result ->
       check_eq "identical builds: total nodes" (string_of_int result.dr_total) "2";
       check_eq "identical builds: unchanged count" (string_of_int result.dr_unchanged) "2";
       check_eq "identical builds: changed count" (string_of_int result.dr_changed) "0";
       check_eq "identical builds: added count" (string_of_int result.dr_added) "0";
       check_eq "identical builds: removed count" (string_of_int result.dr_removed) "0";
       check "identical builds: all nodes are Unchanged"
         (List.for_all (fun e -> match e.Builder_diff.nde_status with Builder_diff.Unchanged _ -> true | _ -> false) result.dr_nodes));
  remove_path dir1;

  (* Test 2: one node changed -> detects change *)
  let dir2 = make_temp_dir () in
  let log_a2 = Filename.concat dir2 "build_log_20260101_120000_aaa.json" in
  let log_b2 = Filename.concat dir2 "build_log_20260101_130000_ccc.json" in
  let log_build_a = {|{
    "timestamp": "20260101_120000",
    "hash": "aaa111",
    "out_path": "/nix/store/aaa111-pipeline_output",
    "duration": 1.0,
    "pipeline": "test_pipeline",
    "nodes": [
      {"node": "read_data", "path": "/nix/store/aaa111-pipeline_output/read_data/artifact", "hash": "aaa111", "runtime": "T", "serializer": "default", "class": "VDataFrame", "dependencies": [], "status": "Completed", "success": true, "warnings": false, "duration": 0.3},
      {"node": "clean", "path": "/nix/store/bbb222-pipeline_output/clean/artifact", "hash": "bbb222", "runtime": "T", "serializer": "default", "class": "VDataFrame", "dependencies": ["read_data"], "status": "Completed", "success": true, "warnings": false, "duration": 0.2}
    ]
  }|} in
  let log_build_b = {|{
    "timestamp": "20260101_130000",
    "hash": "ccc333",
    "out_path": "/nix/store/ccc333-pipeline_output",
    "duration": 1.0,
    "pipeline": "test_pipeline",
    "nodes": [
      {"node": "read_data", "path": "/nix/store/aaa111-pipeline_output/read_data/artifact", "hash": "aaa111", "runtime": "T", "serializer": "default", "class": "VDataFrame", "dependencies": [], "status": "Completed", "success": true, "warnings": false, "duration": 0.3},
      {"node": "clean", "path": "/nix/store/ddd444-pipeline_output/clean/artifact", "hash": "ddd444", "runtime": "T", "serializer": "default", "class": "VDataFrame", "dependencies": ["read_data"], "status": "Completed", "success": true, "warnings": false, "duration": 0.2}
    ]
  }|} in
  write_file log_a2 log_build_a;
  write_file log_b2 log_build_b;
  (match Builder_diff.compute_diff log_a2 log_b2 with
   | Error msg ->
       Printf.printf "  \xe2\x9c\x97 changed node: %s\n" msg;
       incr fail_count
   | Ok result ->
       check_eq "changed node: total nodes" (string_of_int result.dr_total) "2";
       check_eq "changed node: unchanged count" (string_of_int result.dr_unchanged) "1";
       check_eq "changed node: changed count" (string_of_int result.dr_changed) "1";
       let changed_node = List.find (fun e -> e.Builder_diff.nde_name = "clean") result.dr_nodes in
       (match changed_node.Builder_diff.nde_status with
        | Builder_diff.Changed { hash_a; hash_b } ->
            check_eq "changed node: hash_a" hash_a "bbb222";
            check_eq "changed node: hash_b" hash_b "ddd444"
        | _ -> check "changed node: clean is Changed" false));
  remove_path dir2;

  (* Test 3: node added *)
  let dir3 = make_temp_dir () in
  let log_a3 = Filename.concat dir3 "build_log_20260101_120000_aaa.json" in
  let log_b3 = Filename.concat dir3 "build_log_20260101_130000_eee.json" in
  let log_a_only = {|{
    "timestamp": "20260101_120000",
    "hash": "aaa111",
    "out_path": "/nix/store/aaa111-pipeline_output",
    "duration": 1.0,
    "pipeline": "test_pipeline",
    "nodes": [
      {"node": "read_data", "path": "/nix/store/aaa111-pipeline_output/read_data/artifact", "hash": "aaa111", "runtime": "T", "serializer": "default", "class": "VDataFrame", "dependencies": [], "status": "Completed", "success": true, "warnings": false, "duration": 0.3}
    ]
  }|} in
  let log_b_with_new = {|{
    "timestamp": "20260101_130000",
    "hash": "eee555",
    "out_path": "/nix/store/eee555-pipeline_output",
    "duration": 1.0,
    "pipeline": "test_pipeline",
    "nodes": [
      {"node": "read_data", "path": "/nix/store/aaa111-pipeline_output/read_data/artifact", "hash": "aaa111", "runtime": "T", "serializer": "default", "class": "VDataFrame", "dependencies": [], "status": "Completed", "success": true, "warnings": false, "duration": 0.3},
      {"node": "new_node", "path": "/nix/store/fff666-pipeline_output/new_node/artifact", "hash": "fff666", "runtime": "T", "serializer": "default", "class": "VDataFrame", "dependencies": [], "status": "Completed", "success": true, "warnings": false, "duration": 0.1}
    ]
  }|} in
  write_file log_a3 log_a_only;
  write_file log_b3 log_b_with_new;
  (match Builder_diff.compute_diff log_a3 log_b3 with
   | Error msg ->
       Printf.printf "  \xe2\x9c\x97 added node: %s\n" msg;
       incr fail_count
   | Ok result ->
       check_eq "added node: total nodes" (string_of_int result.dr_total) "2";
       check_eq "added node: added count" (string_of_int result.dr_added) "1";
       let added_node = List.find (fun e -> e.Builder_diff.nde_name = "new_node") result.dr_nodes in
       (match added_node.Builder_diff.nde_status with
        | Builder_diff.Added { hash } -> check_eq "added node: hash" hash "fff666"
        | _ -> check "added node: new_node is Added" false));
  remove_path dir3;

  (* Test 4: node removed *)
  let dir4 = make_temp_dir () in
  let log_a4 = Filename.concat dir4 "build_log_20260101_120000_aaa.json" in
  let log_b4 = Filename.concat dir4 "build_log_20260101_130000_ggg.json" in
  let log_a_full = {|{
    "timestamp": "20260101_120000",
    "hash": "aaa111",
    "out_path": "/nix/store/aaa111-pipeline_output",
    "duration": 1.0,
    "pipeline": "test_pipeline",
    "nodes": [
      {"node": "read_data", "path": "/nix/store/aaa111-pipeline_output/read_data/artifact", "hash": "aaa111", "runtime": "T", "serializer": "default", "class": "VDataFrame", "dependencies": [], "status": "Completed", "success": true, "warnings": false, "duration": 0.3},
      {"node": "removed_node", "path": "/nix/store/hhh777-pipeline_output/removed_node/artifact", "hash": "hhh777", "runtime": "T", "serializer": "default", "class": "VDataFrame", "dependencies": [], "status": "Completed", "success": true, "warnings": false, "duration": 0.1}
    ]
  }|} in
  let log_b_smaller = {|{
    "timestamp": "20260101_130000",
    "hash": "ggg888",
    "out_path": "/nix/store/ggg888-pipeline_output",
    "duration": 1.0,
    "pipeline": "test_pipeline",
    "nodes": [
      {"node": "read_data", "path": "/nix/store/aaa111-pipeline_output/read_data/artifact", "hash": "aaa111", "runtime": "T", "serializer": "default", "class": "VDataFrame", "dependencies": [], "status": "Completed", "success": true, "warnings": false, "duration": 0.3}
    ]
  }|} in
  write_file log_a4 log_a_full;
  write_file log_b4 log_b_smaller;
  (match Builder_diff.compute_diff log_a4 log_b4 with
   | Error msg ->
       Printf.printf "  \xe2\x9c\x97 removed node: %s\n" msg;
       incr fail_count
   | Ok result ->
       check_eq "removed node: total nodes" (string_of_int result.dr_total) "2";
       check_eq "removed node: removed count" (string_of_int result.dr_removed) "1";
       let removed_node = List.find (fun e -> e.Builder_diff.nde_name = "removed_node") result.dr_nodes in
       (match removed_node.Builder_diff.nde_status with
        | Builder_diff.Removed { hash } -> check_eq "removed node: hash" hash "hhh777"
        | _ -> check "removed node: removed_node is Removed" false));
  remove_path dir4;

  (* Test 5: JSON output *)
  Printf.printf "\nBuilder_diff — JSON output:\n";
  let dir5 = make_temp_dir () in
  let log_a5 = Filename.concat dir5 "build_log_20260101_120000_aaa.json" in
  let log_b5 = Filename.concat dir5 "build_log_20260101_130000_jjj.json" in
  write_file log_a5 log_build_a;
  write_file log_b5 log_build_b;
  (match Builder_diff.compute_diff log_a5 log_b5 with
   | Error msg ->
       Printf.printf "  \xe2\x9c\x97 JSON output: %s\n" msg;
       incr fail_count
   | Ok result ->
       let json_str = Yojson.Safe.pretty_to_string (Builder.diff_result_to_yojson result) in
       check "JSON output: contains schema_version"
         (try let _ = Str.search_forward (Str.regexp_string "\"schema_version\"") json_str 0 in true with Not_found -> false);
       check "JSON output: contains phase diff"
         (try let _ = Str.search_forward (Str.regexp_string "\"phase\"") json_str 0 in true with Not_found -> false);
       check "JSON output: contains build_a"
         (try let _ = Str.search_forward (Str.regexp_string "\"build_a\"") json_str 0 in true with Not_found -> false);
       check "JSON output: contains build_b"
         (try let _ = Str.search_forward (Str.regexp_string "\"build_b\"") json_str 0 in true with Not_found -> false);
       check "JSON output: contains summary"
         (try let _ = Str.search_forward (Str.regexp_string "\"summary\"") json_str 0 in true with Not_found -> false));
  remove_path dir5;

  Printf.printf "\n"
