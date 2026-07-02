let run_tests pass_count fail_count _failures _eval_string _eval_string_env _test =
  let report ok msg fail_msg =
    if ok then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" msg
    end else begin
      incr fail_count;
      Printf.printf "  ✗ %s\n" fail_msg
    end
  in
  let get_field name = function
    | Ast.VDict pairs -> List.assoc_opt name pairs
    | _ -> None
  in
  Printf.printf "Diff — Generic:\n";
  let list_diff =
    Diff.node_diff_values
      ~va:(Ast.VList [(None, Ast.VInt 1); (None, Ast.VInt 2)])
      ~vb:(Ast.VList [(None, Ast.VInt 1); (None, Ast.VInt 3)])
      ~node_a_name:"items" ~node_b_name:"items"
      ~log_a:"build_a" ~log_b:"build_b"
      ~key:[] ~context:1
  in
  report (match get_field "kind" list_diff with Some (Ast.VString "generic_diff") -> true | _ -> false)
    "lists fall back to generic diffs"
    "list diffs should use generic_diff";
  let dict_diff =
    Diff.node_diff_values
      ~va:(Ast.VDict [("x", Ast.VInt 1); ("y", Ast.VInt 2)])
      ~vb:(Ast.VDict [("x", Ast.VInt 1); ("y", Ast.VInt 2)])
      ~node_a_name:"cfg" ~node_b_name:"cfg"
      ~log_a:"build_a" ~log_b:"build_a"
      ~key:[] ~context:1
  in
  report (match get_field "identical" dict_diff with Some (Ast.VBool true) -> true | _ -> false)
    "generic diffs preserve identical path"
    "identical generic values should set identical=true";
  let error_diff =
    Diff.node_diff_values
      ~va:(Error.make_error Ast.ValueError "before")
      ~vb:(Error.make_error Ast.ValueError "after")
      ~node_a_name:"err" ~node_b_name:"err"
      ~log_a:"build_a" ~log_b:"build_b"
      ~key:[] ~context:1
  in
  report (match get_field "identical" error_diff with Some (Ast.VBool false) -> true | _ -> false)
    "generic diffs handle error values"
    "error generic diff should detect changes";
  let julia_runtime_missing_or_supported =
    let make_node path class_name =
      Ast.VComputedNode {
        cn_name = "weights";
        cn_runtime = "Julia";
        cn_path = path;
        cn_serializer = "default";
        cn_class = class_name;
        cn_dependencies = [];
        cn_p_exprs = None;
        cn_flake = None;
      }
    in
    let artifact_a = Filename.temp_file "tlang-julia-node-a" ".jls" in
    let artifact_b = Filename.temp_file "tlang-julia-node-b" ".jls" in
    Fun.protect
      ~finally:(fun () ->
        if Sys.file_exists artifact_a then Sys.remove artifact_a;
        if Sys.file_exists artifact_b then Sys.remove artifact_b)
      (fun () ->
        let value =
          Diff.node_diff_values
            ~va:(make_node artifact_a "ModelSnapshot")
            ~vb:(make_node artifact_b "ModelSnapshot")
            ~node_a_name:"weights" ~node_b_name:"weights"
            ~log_a:"build_a" ~log_b:"build_b"
            ~key:[] ~context:1
        in
        match value with
        | Ast.VDict fields ->
            List.assoc_opt "kind" fields = Some (Ast.VString "julia_object_diff")
        | Ast.VError { Ast.code = RuntimeError | FileError; _ } -> true
        | _ -> false)
  in
  report julia_runtime_missing_or_supported
    "Julia computed nodes route through the Julia object diff path"
    "Julia computed nodes should produce a Julia diff result or a structured runtime/file error";
  let r_runtime_missing_or_supported =
    let make_node path class_name =
      Ast.VComputedNode {
        cn_name = "model";
        cn_runtime = "R";
        cn_path = path;
        cn_serializer = "default";
        cn_class = class_name;
        cn_dependencies = [];
        cn_p_exprs = None;
        cn_flake = None;
      }
    in
    let artifact_a = Filename.temp_file "tlang-r-node-a" ".rds" in
    let artifact_b = Filename.temp_file "tlang-r-node-b" ".rds" in
    Fun.protect
      ~finally:(fun () ->
        if Sys.file_exists artifact_a then Sys.remove artifact_a;
        if Sys.file_exists artifact_b then Sys.remove artifact_b)
      (fun () ->
        let value =
          Diff.node_diff_values
            ~va:(make_node artifact_a "lm")
            ~vb:(make_node artifact_b "lm")
            ~node_a_name:"model" ~node_b_name:"model"
            ~log_a:"build_a" ~log_b:"build_b"
            ~key:[] ~context:1
        in
        match value with
        | Ast.VDict fields ->
            List.assoc_opt "kind" fields = Some (Ast.VString "r_object_diff")
        | Ast.VError { Ast.code = RuntimeError | FileError; _ } -> true
        | _ -> false)
  in
  report r_runtime_missing_or_supported
    "R computed nodes route through the R object diff path"
    "R computed nodes should produce an R diff result or a structured runtime/file error";
  print_newline ()
