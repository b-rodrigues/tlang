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
  let model_a =
    Ast.VDict [
      ("model_type", Ast.VString "lm");
      ("coefficients", Ast.VDict [("x", Ast.VFloat 1.0); ("y", Ast.VFloat 2.0)]);
      ("r_squared", Ast.VFloat 0.5);
      ("aic", Ast.VFloat 100.0);
    ]
  in
  let model_b =
    Ast.VDict [
      ("model_type", Ast.VString "lm");
      ("coefficients", Ast.VDict [("x", Ast.VFloat 1.5); ("z", Ast.VFloat 3.0)]);
      ("r_squared", Ast.VFloat 0.7);
      ("aic", Ast.VFloat 95.0);
    ]
  in
  Printf.printf "Diff — Model:\n";
  let diff =
    Diff.node_diff_values
      ~va:model_a ~vb:model_b
      ~node_a_name:"model" ~node_b_name:"model"
      ~log_a:"build_a" ~log_b:"build_b"
      ~key:[] ~context:1
  in
  (match get_field "summary" diff with
   | Some (Ast.VDict summary) ->
       let int_field name = match List.assoc_opt name summary with Some (Ast.VInt n) -> n | _ -> -1 in
       let float_field name = match List.assoc_opt name summary with Some (Ast.VFloat f) -> f | _ -> nan in
       let approx a b = Float.abs (a -. b) < 1e-9 in
       report (int_field "coef_changed" = 1
               && int_field "coef_added" = 1
               && int_field "coef_removed" = 1
               && approx (float_field "r2_delta") 0.2
               && approx (float_field "aic_delta") (-5.0))
         "model summary reports coefficient and fit-stat deltas"
         "model summary mismatch"
   | _ -> report false "model summary reports coefficient and fit-stat deltas" "model summary missing");
  let identical =
    Diff.node_diff_values
      ~va:model_a ~vb:model_a
      ~node_a_name:"model" ~node_b_name:"model"
      ~log_a:"build_a" ~log_b:"build_a"
      ~key:[] ~context:1
  in
  report (match get_field "identical" identical with Some (Ast.VBool true) -> true | _ -> false)
    "identical models short-circuit correctly"
    "identical models should set identical=true";
  print_newline ()
