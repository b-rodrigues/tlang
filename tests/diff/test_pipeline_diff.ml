let run_tests pass_count fail_count _failures _eval_string eval_string_env _test =
  let report ok msg fail_msg =
    if ok then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" msg
    end else begin
      incr fail_count;
      Printf.printf "  ✗ %s\n" fail_msg
    end
  in
  let rec remove_path path =
    if Sys.file_exists path then
      if Sys.is_directory path then begin
        Sys.readdir path
        |> Array.iter (fun name -> remove_path (Filename.concat path name));
        Unix.rmdir path
      end else
        Sys.remove path
  in
  let with_temp_pipeline_project f =
    let rec make_temp_dir attempts =
      if attempts <= 0 then failwith "failed to create temporary diff test directory"
      else
        let candidate =
          Filename.concat
            (Filename.get_temp_dir_name ())
            (Printf.sprintf "tlang-diff-%d-%06d" (Unix.getpid ()) (Random.int 1_000_000))
        in
        try
          Unix.mkdir candidate 0o755;
          candidate
        with Unix.Unix_error (Unix.EEXIST, _, _) ->
          make_temp_dir (attempts - 1)
    in
    let dir = make_temp_dir 8 in
    let old_cwd = Sys.getcwd () in
    try
      Sys.chdir dir;
      let result = f dir in
      Sys.chdir old_cwd;
      remove_path dir;
      result
    with exn ->
      Sys.chdir old_cwd;
      remove_path dir;
      raise exn
  in
  Printf.printf "Diff — Pipeline:\n";
  let (diff_value, _) =
    eval_string_env
      {|p_a = pipeline { a = 1; b = a + 1; c = b + 1 }
        p_b = pipeline { a = 1; c = a + 2; d = c + 1 }
        pipeline_diff(p_a, p_b)|}
      (Packages.init_env ())
  in
  (match diff_value with
   | Ast.VDict fields ->
       let list_has name expected =
         match List.assoc_opt name fields with
         | Some (Ast.VList items) -> List.exists (fun (_, v) -> v = Ast.VString expected) items
         | _ -> false
       in
       let rewired_c =
         match List.assoc_opt "rewired_edges" fields with
         | Some (Ast.VList items) ->
             List.exists (fun (_, v) ->
               match v with
               | Ast.VDict row -> List.assoc_opt "name" row = Some (Ast.VString "c")
               | _ -> false) items
         | _ -> false
       in
       let frames_ok =
         match List.assoc_opt "frame_a" fields, List.assoc_opt "frame_b" fields with
         | Some (Ast.VDataFrame _), Some (Ast.VDataFrame _) -> true
         | _ -> false
       in
       report (List.assoc_opt "kind" fields = Some (Ast.VString "pipeline_diff")
               && list_has "added_nodes" "d"
               && list_has "removed_nodes" "b"
               && list_has "changed_nodes" "c"
               && rewired_c
               && frames_ok)
         "pipeline_diff reports structural changes and rewires"
         "pipeline_diff summary mismatch"
   | other ->
       report false "pipeline_diff reports structural changes and rewires"
         (Printf.sprintf "pipeline_diff returned %s" (Ast.Utils.value_to_string other)));
  let (identical_value, _) =
    eval_string_env
      {|p = pipeline { a = 1; b = a + 1 }
        pipeline_diff(p, p)|}
      (Packages.init_env ())
  in
  report (match identical_value with
      | Ast.VDict fields -> List.assoc_opt "identical" fields = Some (Ast.VBool true)
      | _ -> false)
    "pipeline_diff detects identical pipelines"
    "identical pipelines should set identical=true";
  let (explain_value, _) =
    eval_string_env
      {|p_a = pipeline { a = 1; b = a + 1 }
        p_b = pipeline { a = 1; c = a + 1 }
        explain(pipeline_diff(p_a, p_b))|}
      (Packages.init_env ())
  in
  report (match explain_value with
      | Ast.VDict fields -> List.assoc_opt "kind" fields = Some (Ast.VString "VDiff (pipeline_diff)")
      | _ -> false)
    "pipeline_diff integrates with explain()"
    "explain(pipeline_diff(...)) should produce a structured summary";
  let computed_node_ok =
    with_temp_pipeline_project (fun _dir ->
      Unix.mkdir "_pipeline" 0o755;
      ignore (Serialization.serialize_to_file "node_a_1.tobj" (Ast.VInt 10));
      ignore (Serialization.serialize_to_file "node_a_2.tobj" (Ast.VInt 20));
      let write_file path contents =
        let oc = open_out path in
        output_string oc contents;
        close_out oc
      in
      write_file "_pipeline/build_log_test1.json"
        {|{"timestamp":"2026-05-25T12:00:00Z","duration":1.0,"hash":"hash1","out_path":"/nix/store/a","nodes":[{"node":"a","path":"node_a_1.tobj","runtime":"T","serializer":"default","class":"V","dependencies":[],"success":"true"}]}|};
      write_file "_pipeline/build_log_test2.json"
        {|{"timestamp":"2026-05-25T13:00:00Z","duration":1.0,"hash":"hash2","out_path":"/nix/store/b","nodes":[{"node":"a","path":"node_a_2.tobj","runtime":"T","serializer":"default","class":"V","dependencies":[],"success":"true"}]}|};
      match eval_string_env
              {|p = pipeline { a = 1 }
                d = node_diff(p.a, p.a, log_a = ".*test1.*", log_b = ".*test2.*")
                d.kind == "scalar_diff" && d.summary.delta == 10|}
              (Packages.init_env ()) with
      | Ast.VBool true, _ -> true
      | _ -> false)
  in
  report computed_node_ok
    "node_diff supports the ComputedNode calling convention"
    "ComputedNode node_diff call did not resolve historical artifacts";
  print_newline ()
