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
  print_newline ()
