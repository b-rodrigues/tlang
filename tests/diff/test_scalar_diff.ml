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
  let summary_field name = function
    | Some (Ast.VDict summary) -> List.assoc_opt name summary
    | _ -> None
  in
  Printf.printf "Diff — Scalar:\n";
  let int_diff =
    Diff.node_diff_values
      ~va:(Ast.VInt 10) ~vb:(Ast.VInt 15)
      ~node_a_name:"score" ~node_b_name:"score"
      ~log_a:"build_a" ~log_b:"build_b"
      ~key:[] ~context:0
  in
  report (summary_field "delta" (get_field "summary" int_diff) = Some (Ast.VInt 5))
    "integer scalars compute numeric delta"
    "integer delta mismatch";
  let bool_diff =
    Diff.node_diff_values
      ~va:(Ast.VBool false) ~vb:(Ast.VBool true)
      ~node_a_name:"flag" ~node_b_name:"flag"
      ~log_a:"build_a" ~log_b:"build_b"
      ~key:[] ~context:0
  in
  report (summary_field "delta" (get_field "summary" bool_diff) = Some (Ast.VNA Ast.NAGeneric))
    "non-numeric scalars return NA delta"
    "bool delta should be NA";
  let nan_diff =
    Diff.node_diff_values
      ~va:(Ast.VFloat nan) ~vb:(Ast.VFloat nan)
      ~node_a_name:"metric" ~node_b_name:"metric"
      ~log_a:"build_a" ~log_b:"build_b"
      ~key:[] ~context:0
  in
  report (match get_field "identical" nan_diff with Some (Ast.VBool true) -> true | _ -> false)
    "NaN scalar comparisons use semantic equality"
    "NaN comparisons should be identical";
  print_newline ()
