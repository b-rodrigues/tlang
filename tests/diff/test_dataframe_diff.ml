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
  let make_df ids values extras =
    let n = List.length ids in
    let id_arr = Array.of_list (List.map Option.some ids) in
    let value_arr = Array.of_list (List.map Option.some values) in
    let cols = [
      ("id", Arrow_table.IntColumn id_arr);
      ("value", Arrow_table.IntColumn value_arr);
    ] @ (match extras with
      | None -> []
      | Some xs -> [("region", Arrow_table.StringColumn (Array.of_list (List.map Option.some xs)))])
    in
    let arrow_table = Arrow_table.create cols n in
    Ast.VDataFrame { arrow_table; group_keys = [] }
  in
  let expect_counts label diff rows_added rows_removed rows_changed identical =
    match get_field "summary" diff with
    | Some (Ast.VDict summary) ->
        let int_field name = match List.assoc_opt name summary with Some (Ast.VInt n) -> n | _ -> -1 in
        let bool_identical = match get_field "identical" diff with Some (Ast.VBool b) -> b | _ -> not identical in
        report (int_field "rows_added" = rows_added
                && int_field "rows_removed" = rows_removed
                && int_field "rows_changed" = rows_changed
                && bool_identical = identical)
          label
          (Printf.sprintf "%s counts mismatch" label)
    | _ -> report false label (Printf.sprintf "%s summary missing" label)
  in
  Printf.printf "Diff — DataFrame:\n";
  let df_a = make_df [1; 2; 3] [10; 20; 30] None in
  let df_b = make_df [1; 2; 4] [10; 25; 40] (Some ["north"; "south"; "west"]) in
  let keyed =
    Diff.node_diff_values
      ~va:df_a ~vb:df_b
      ~node_a_name:"customers" ~node_b_name:"customers"
      ~log_a:"build_a" ~log_b:"build_b"
      ~key:["id"] ~context:1
  in
  expect_counts "keyed row alignment reports add/remove/change" keyed 1 1 1 false;
  (match get_field "summary" keyed with
   | Some (Ast.VDict summary) ->
       let has_region =
         match List.assoc_opt "cols_added" summary with
         | Some (Ast.VList items) -> List.exists (fun (_, v) -> v = Ast.VString "region") items
         | _ -> false
       in
       report has_region "schema additions are reported" "schema additions missing"
   | _ -> report false "schema additions are reported" "schema additions summary missing");
  let positional_a = make_df [1; 2] [10; 20] None in
  let positional_b = make_df [1; 2] [15; 20] None in
  let positional =
    Diff.node_diff_values
      ~va:positional_a ~vb:positional_b
      ~node_a_name:"orders" ~node_b_name:"orders"
      ~log_a:"build_a" ~log_b:"build_b"
      ~key:[] ~context:0
  in
  expect_counts "positional row alignment reports changed rows" positional 0 0 1 false;
  let identical =
    Diff.node_diff_values
      ~va:positional_a ~vb:positional_a
      ~node_a_name:"orders" ~node_b_name:"orders"
      ~log_a:"build_a" ~log_b:"build_a"
      ~key:["id"] ~context:2
  in
  expect_counts "identical dataframes set identical=true" identical 0 0 0 true;
  print_newline ()
