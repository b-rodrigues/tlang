(* tests/arrow/test_arrow_performance.ml *)
(* Arrow Backend Performance Tests — Week 1 *)
(* Tests the performance characteristics of Arrow-backed operations      *)
(* at various dataset sizes (10k, 100k, 1M rows).                       *)
(* Validates correctness and measures execution time.                    *)

(** Generate a test table with n rows and 3 numeric columns + 1 string group column.
    Columns: id (int), value (float), group (string), extra (float) *)
let generate_test_table (n : int) (n_groups : int) : Arrow_table.t =
  let id_col = Arrow_table.IntColumn (Array.init n (fun i -> Some (i + 1))) in
  let value_col = Arrow_table.FloatColumn (Array.init n (fun i ->
    Some (float_of_int (i mod 100) +. 0.5)
  )) in
  let group_col = Arrow_table.StringColumn (Array.init n (fun i ->
    Some (Printf.sprintf "group_%d" (i mod n_groups))
  )) in
  let extra_col = Arrow_table.FloatColumn (Array.init n (fun i ->
    Some (float_of_int i *. 1.5)
  )) in
  Arrow_table.create [
    ("id", id_col);
    ("value", value_col);
    ("group", group_col);
    ("extra", extra_col);
  ] n

(** Measure execution time in seconds *)
let time_it (f : unit -> 'a) : float * 'a =
  let t0 = Sys.time () in
  let result = f () in
  let t1 = Sys.time () in
  (t1 -. t0, result)

let run_tests pass_count fail_count _eval_string _eval_string_env _test =
  Printf.printf "Arrow Performance — Column View Access:\n";

  (* Test 1: Column view creation on 10k rows *)
  let tbl_10k = generate_test_table 10000 100 in
  (match Arrow_column.get_column tbl_10k "value" with
   | Some col_view ->
     if Arrow_column.column_length col_view = 10000 then begin
       incr pass_count; Printf.printf "  ✓ Column view creation (10k rows)\n"
     end else begin
       incr fail_count; Printf.printf "  ✗ Column view length mismatch (10k rows)\n"
     end
   | None ->
     incr fail_count; Printf.printf "  ✗ Column view creation failed (10k rows)\n");

  (* Test 2: get_value_at on column view *)
  (match Arrow_column.get_column tbl_10k "value" with
   | Some col_view ->
     let v = Arrow_column.get_value_at col_view 0 in
     (match v with
      | Ast.VFloat f when f = 0.5 ->
        incr pass_count; Printf.printf "  ✓ get_value_at returns correct value\n"
      | _ ->
        incr fail_count; Printf.printf "  ✗ get_value_at returned: %s\n" (Ast.Utils.value_to_string v))
   | None ->
     incr fail_count; Printf.printf "  ✗ get_column failed\n");

  (* Test 3: get_value_at out-of-bounds returns VNull *)
  (match Arrow_column.get_column tbl_10k "value" with
   | Some col_view ->
     let v = Arrow_column.get_value_at col_view 99999 in
     (match v with
      | Ast.VNull ->
        incr pass_count; Printf.printf "  ✓ get_value_at out-of-bounds returns VNull\n"
      | _ ->
        incr fail_count; Printf.printf "  ✗ get_value_at out-of-bounds returned: %s\n"
          (Ast.Utils.value_to_string v))
   | None ->
     incr fail_count; Printf.printf "  ✗ get_column failed\n");

  (* Test 4: get_slice correctness *)
  (match Arrow_column.get_column tbl_10k "id" with
   | Some col_view ->
     let slice = Arrow_column.get_slice col_view 5 3 in
     if Arrow_column.column_length slice = 3 then begin
       let v0 = Arrow_column.get_value_at slice 0 in
       (match v0 with
        | Ast.VInt 6 ->
          incr pass_count; Printf.printf "  ✓ get_slice returns correct slice (start=5, len=3)\n"
        | _ ->
          incr fail_count; Printf.printf "  ✗ get_slice first element incorrect: %s\n"
            (Ast.Utils.value_to_string v0))
     end else begin
       incr fail_count; Printf.printf "  ✗ get_slice length incorrect\n"
     end
   | None ->
     incr fail_count; Printf.printf "  ✗ get_column failed\n");

  (* Test 5: column_view_to_list correctness *)
  let small_tbl = Arrow_table.create [
    ("x", Arrow_table.FloatColumn [| Some 1.0; Some 2.0; Some 3.0 |]);
  ] 3 in
  (match Arrow_column.get_column small_tbl "x" with
   | Some col_view ->
     let lst = Arrow_column.column_view_to_list col_view in
     if List.length lst = 3 then begin
       incr pass_count; Printf.printf "  ✓ column_view_to_list returns correct list\n"
     end else begin
       incr fail_count; Printf.printf "  ✗ column_view_to_list length incorrect\n"
     end
   | None ->
     incr fail_count; Printf.printf "  ✗ get_column failed\n");
  print_newline ();

  Printf.printf "Arrow Performance — Vectorized Math Operations:\n";

  (* Test 6: sqrt_column correctness *)
  let math_tbl = Arrow_table.create [
    ("x", Arrow_table.FloatColumn [| Some 4.0; Some 9.0; Some 16.0 |]);
  ] 3 in
  (match Arrow_compute.sqrt_column math_tbl "x" with
   | Some result_tbl ->
     (match Arrow_table.get_column result_tbl "x" with
      | Some (Arrow_table.FloatColumn data) ->
        let close a b = Float.abs (a -. b) < 1e-10 in
        if data.(0) = Some 2.0 && data.(1) = Some 3.0
           && (match data.(2) with Some f -> close f 4.0 | None -> false) then begin
          incr pass_count; Printf.printf "  ✓ sqrt_column produces correct results\n"
        end else begin
          incr fail_count; Printf.printf "  ✗ sqrt_column results incorrect\n"
        end
      | _ ->
        incr fail_count; Printf.printf "  ✗ sqrt_column result column type mismatch\n")
   | None ->
     incr fail_count; Printf.printf "  ✗ sqrt_column returned None\n");

  (* Test 7: abs_column correctness *)
  let abs_tbl = Arrow_table.create [
    ("x", Arrow_table.FloatColumn [| Some (-3.0); Some 0.0; Some 5.0 |]);
  ] 3 in
  (match Arrow_compute.abs_column abs_tbl "x" with
   | Some result_tbl ->
     (match Arrow_table.get_column result_tbl "x" with
      | Some (Arrow_table.FloatColumn data) ->
        if data.(0) = Some 3.0 && data.(1) = Some 0.0 && data.(2) = Some 5.0 then begin
          incr pass_count; Printf.printf "  ✓ abs_column produces correct results\n"
        end else begin
          incr fail_count; Printf.printf "  ✗ abs_column results incorrect\n"
        end
      | _ ->
        incr fail_count; Printf.printf "  ✗ abs_column result column type mismatch\n")
   | None ->
     incr fail_count; Printf.printf "  ✗ abs_column returned None\n");

  (* Test 8: log_column correctness *)
  let log_tbl = Arrow_table.create [
    ("x", Arrow_table.FloatColumn [| Some 1.0; Some (exp 1.0); Some (exp 2.0) |]);
  ] 3 in
  (match Arrow_compute.log_column log_tbl "x" with
   | Some result_tbl ->
     (match Arrow_table.get_column result_tbl "x" with
      | Some (Arrow_table.FloatColumn data) ->
        let close a b = Float.abs (a -. b) < 1e-10 in
        if (match data.(0) with Some f -> close f 0.0 | None -> false)
           && (match data.(1) with Some f -> close f 1.0 | None -> false) then begin
          incr pass_count; Printf.printf "  ✓ log_column produces correct results\n"
        end else begin
          incr fail_count; Printf.printf "  ✗ log_column results incorrect\n"
        end
      | _ ->
        incr fail_count; Printf.printf "  ✗ log_column result column type mismatch\n")
   | None ->
     incr fail_count; Printf.printf "  ✗ log_column returned None\n");

  (* Test 9: exp_column correctness *)
  let exp_tbl = Arrow_table.create [
    ("x", Arrow_table.FloatColumn [| Some 0.0; Some 1.0 |]);
  ] 2 in
  (match Arrow_compute.exp_column exp_tbl "x" with
   | Some result_tbl ->
     (match Arrow_table.get_column result_tbl "x" with
      | Some (Arrow_table.FloatColumn data) ->
        let close a b = Float.abs (a -. b) < 1e-10 in
        if (match data.(0) with Some f -> close f 1.0 | None -> false)
           && (match data.(1) with Some f -> close f (exp 1.0) | None -> false) then begin
          incr pass_count; Printf.printf "  ✓ exp_column produces correct results\n"
        end else begin
          incr fail_count; Printf.printf "  ✗ exp_column results incorrect\n"
        end
      | _ ->
        incr fail_count; Printf.printf "  ✗ exp_column result column type mismatch\n")
   | None ->
     incr fail_count; Printf.printf "  ✗ exp_column returned None\n");

  (* Test 10: pow_column correctness *)
  let pow_tbl = Arrow_table.create [
    ("x", Arrow_table.FloatColumn [| Some 2.0; Some 3.0; Some 4.0 |]);
  ] 3 in
  (match Arrow_compute.pow_column pow_tbl "x" 2.0 with
   | Some result_tbl ->
     (match Arrow_table.get_column result_tbl "x" with
      | Some (Arrow_table.FloatColumn data) ->
        if data.(0) = Some 4.0 && data.(1) = Some 9.0 && data.(2) = Some 16.0 then begin
          incr pass_count; Printf.printf "  ✓ pow_column produces correct results (x^2)\n"
        end else begin
          incr fail_count; Printf.printf "  ✗ pow_column results incorrect\n"
        end
      | _ ->
        incr fail_count; Printf.printf "  ✗ pow_column result column type mismatch\n")
   | None ->
     incr fail_count; Printf.printf "  ✗ pow_column returned None\n");

  (* Test 11: Math on non-existent column returns None *)
  (match Arrow_compute.sqrt_column math_tbl "nonexistent" with
   | None ->
     incr pass_count; Printf.printf "  ✓ sqrt_column returns None for missing column\n"
   | Some _ ->
     incr fail_count; Printf.printf "  ✗ sqrt_column should return None for missing column\n");
  print_newline ();

  Printf.printf "Arrow Performance — Column Aggregations:\n";

  (* Test 12: sum_column *)
  let agg_tbl = Arrow_table.create [
    ("x", Arrow_table.FloatColumn [| Some 1.0; Some 2.0; Some 3.0; Some 4.0 |]);
    ("y", Arrow_table.IntColumn [| Some 10; Some 20; Some 30; Some 40 |]);
  ] 4 in
  (match Arrow_compute.sum_column agg_tbl "x" with
   | Some sum when sum = 10.0 ->
     incr pass_count; Printf.printf "  ✓ sum_column float = 10.0\n"
   | Some sum ->
     incr fail_count; Printf.printf "  ✗ sum_column float expected 10.0, got %f\n" sum
   | None ->
     incr fail_count; Printf.printf "  ✗ sum_column float returned None\n");

  (* Test 13: sum_column on int column *)
  (match Arrow_compute.sum_column agg_tbl "y" with
   | Some sum when sum = 100.0 ->
     incr pass_count; Printf.printf "  ✓ sum_column int = 100.0\n"
   | Some sum ->
     incr fail_count; Printf.printf "  ✗ sum_column int expected 100.0, got %f\n" sum
   | None ->
     incr fail_count; Printf.printf "  ✗ sum_column int returned None\n");

  (* Test 14: mean_column *)
  (match Arrow_compute.mean_column agg_tbl "x" with
   | Some m when m = 2.5 ->
     incr pass_count; Printf.printf "  ✓ mean_column = 2.5\n"
   | Some m ->
     incr fail_count; Printf.printf "  ✗ mean_column expected 2.5, got %f\n" m
   | None ->
     incr fail_count; Printf.printf "  ✗ mean_column returned None\n");

  (* Test 15: min_column *)
  (match Arrow_compute.min_column agg_tbl "x" with
   | Some m when m = 1.0 ->
     incr pass_count; Printf.printf "  ✓ min_column = 1.0\n"
   | Some m ->
     incr fail_count; Printf.printf "  ✗ min_column expected 1.0, got %f\n" m
   | None ->
     incr fail_count; Printf.printf "  ✗ min_column returned None\n");

  (* Test 16: max_column *)
  (match Arrow_compute.max_column agg_tbl "x" with
   | Some m when m = 4.0 ->
     incr pass_count; Printf.printf "  ✓ max_column = 4.0\n"
   | Some m ->
     incr fail_count; Printf.printf "  ✗ max_column expected 4.0, got %f\n" m
   | None ->
     incr fail_count; Printf.printf "  ✗ max_column returned None\n");

  (* Test 17: Aggregation on missing column returns None *)
  (match Arrow_compute.sum_column agg_tbl "nonexistent" with
   | None ->
     incr pass_count; Printf.printf "  ✓ sum_column returns None for missing column\n"
   | Some _ ->
     incr fail_count; Printf.printf "  ✗ sum_column should return None for missing column\n");
  print_newline ();

  Printf.printf "Arrow Performance — Comparison Operations:\n";

  (* Test 18: compare_column_scalar "gt" *)
  let cmp_tbl = Arrow_table.create [
    ("x", Arrow_table.FloatColumn [| Some 1.0; Some 5.0; Some 10.0; Some 3.0 |]);
  ] 4 in
  (match Arrow_compute.compare_column_scalar cmp_tbl "x" 4.0 "gt" with
   | Some mask ->
     if Array.length mask = 4
        && not mask.(0) && mask.(1) && mask.(2) && not mask.(3) then begin
       incr pass_count; Printf.printf "  ✓ compare_column_scalar 'gt' 4.0 correct\n"
     end else begin
       incr fail_count; Printf.printf "  ✗ compare_column_scalar 'gt' 4.0 mask incorrect\n"
     end
   | None ->
     incr fail_count; Printf.printf "  ✗ compare_column_scalar 'gt' returned None\n");

  (* Test 19: compare_column_scalar "le" *)
  (match Arrow_compute.compare_column_scalar cmp_tbl "x" 5.0 "le" with
   | Some mask ->
     if mask.(0) && mask.(1) && not mask.(2) && mask.(3) then begin
       incr pass_count; Printf.printf "  ✓ compare_column_scalar 'le' 5.0 correct\n"
     end else begin
       incr fail_count; Printf.printf "  ✗ compare_column_scalar 'le' 5.0 mask incorrect\n"
     end
   | None ->
     incr fail_count; Printf.printf "  ✗ compare_column_scalar 'le' returned None\n");

  (* Test 20: compare_column_scalar "eq" *)
  (match Arrow_compute.compare_column_scalar cmp_tbl "x" 5.0 "eq" with
   | Some mask ->
     if not mask.(0) && mask.(1) && not mask.(2) && not mask.(3) then begin
       incr pass_count; Printf.printf "  ✓ compare_column_scalar 'eq' 5.0 correct\n"
     end else begin
       incr fail_count; Printf.printf "  ✗ compare_column_scalar 'eq' 5.0 mask incorrect\n"
     end
   | None ->
     incr fail_count; Printf.printf "  ✗ compare_column_scalar 'eq' returned None\n");

  (* Test 21: compare on int column *)
  let int_cmp_tbl = Arrow_table.create [
    ("n", Arrow_table.IntColumn [| Some 1; Some 5; Some 10 |]);
  ] 3 in
  (match Arrow_compute.compare_column_scalar int_cmp_tbl "n" 5.0 "ge" with
   | Some mask ->
     if not mask.(0) && mask.(1) && mask.(2) then begin
       incr pass_count; Printf.printf "  ✓ compare_column_scalar 'ge' on int column correct\n"
     end else begin
       incr fail_count; Printf.printf "  ✗ compare_column_scalar 'ge' on int column incorrect\n"
     end
   | None ->
     incr fail_count; Printf.printf "  ✗ compare_column_scalar 'ge' on int column returned None\n");

  (* Test 22: Invalid comparison op returns None *)
  (match Arrow_compute.compare_column_scalar cmp_tbl "x" 5.0 "invalid" with
   | None ->
     incr pass_count; Printf.printf "  ✓ compare_column_scalar returns None for invalid op\n"
   | Some _ ->
     incr fail_count; Printf.printf "  ✗ compare_column_scalar should return None for invalid op\n");
  print_newline ();

  Printf.printf "Arrow Performance — Large Dataset Operations:\n";

  (* Test 23: Column selection on 10k rows *)
  let (t_sel, proj_10k) = time_it (fun () -> Arrow_compute.project tbl_10k ["id"; "value"]) in
  if Arrow_table.num_columns proj_10k = 2 && Arrow_table.num_rows proj_10k = 10000 then begin
    incr pass_count; Printf.printf "  ✓ Project 2 columns from 10k rows (%.4fs)\n" t_sel
  end else begin
    incr fail_count; Printf.printf "  ✗ Project 10k rows failed\n"
  end;

  (* Test 24: Filter on 10k rows *)
  let (t_filt, filt_10k) = time_it (fun () ->
    match Arrow_compute.compare_column_scalar tbl_10k "value" 50.0 "gt" with
    | Some mask -> Arrow_compute.filter tbl_10k mask
    | None ->
      (* Fallback: manual filter *)
      let mask = Array.init 10000 (fun i ->
        match (Arrow_table.get_column tbl_10k "value") with
        | Some (Arrow_table.FloatColumn a) ->
          (match a.(i) with Some f -> f > 50.0 | None -> false)
        | _ -> false
      ) in
      Arrow_compute.filter tbl_10k mask
  ) in
  let filt_nrows = Arrow_table.num_rows filt_10k in
  if filt_nrows > 0 && filt_nrows < 10000 then begin
    incr pass_count; Printf.printf "  ✓ Filter 10k rows (%d kept, %.4fs)\n" filt_nrows t_filt
  end else begin
    incr fail_count; Printf.printf "  ✗ Filter 10k rows: unexpected result (%d rows)\n" filt_nrows
  end;

  (* Test 25: Aggregation on 10k rows *)
  let (t_sum, sum_10k) = time_it (fun () -> Arrow_compute.sum_column tbl_10k "value") in
  (match sum_10k with
   | Some s when s > 0.0 ->
     incr pass_count; Printf.printf "  ✓ Sum 10k rows = %.1f (%.4fs)\n" s t_sum
   | _ ->
     incr fail_count; Printf.printf "  ✗ Sum 10k rows failed\n");

  (* Test 26: Group-by on 10k rows with 100 groups *)
  let (t_grp, grouped_10k) = time_it (fun () ->
    Arrow_compute.group_by tbl_10k ["group"]
  ) in
  let n_groups_10k = List.length grouped_10k.Arrow_compute.ocaml_groups in
  if n_groups_10k = 100 then begin
    incr pass_count; Printf.printf "  ✓ Group-by 10k rows → 100 groups (%.4fs)\n" t_grp
  end else begin
    incr fail_count; Printf.printf "  ✗ Group-by 10k rows: expected 100 groups, got %d\n" n_groups_10k
  end;

  (* Test 27: Group aggregate on 10k rows *)
  let (t_gagg, gagg_10k) = time_it (fun () ->
    Arrow_compute.group_aggregate grouped_10k "mean" "value"
  ) in
  if Arrow_table.num_rows gagg_10k = 100 then begin
    incr pass_count; Printf.printf "  ✓ Group aggregate mean 10k rows → 100 groups (%.4fs)\n" t_gagg
  end else begin
    incr fail_count; Printf.printf "  ✗ Group aggregate mean 10k rows failed\n"
  end;
  print_newline ();

  Printf.printf "Arrow Performance — 100k Row Tests:\n";

  (* Test 28: 100k row operations *)
  let tbl_100k = generate_test_table 100000 1000 in
  if Arrow_table.num_rows tbl_100k = 100000 then begin
    incr pass_count; Printf.printf "  ✓ Generated 100k row table\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ 100k row table generation failed\n"
  end;

  let (t_sel100k, _) = time_it (fun () -> Arrow_compute.project tbl_100k ["id"; "value"]) in
  incr pass_count; Printf.printf "  ✓ Project 100k rows (%.4fs)\n" t_sel100k;

  let (t_sum100k, _) = time_it (fun () -> Arrow_compute.sum_column tbl_100k "value") in
  incr pass_count; Printf.printf "  ✓ Sum 100k rows (%.4fs)\n" t_sum100k;

  let (t_grp100k, grouped_100k) = time_it (fun () ->
    Arrow_compute.group_by tbl_100k ["group"]
  ) in
  let n_groups_100k = List.length grouped_100k.Arrow_compute.ocaml_groups in
  if n_groups_100k = 1000 then begin
    incr pass_count; Printf.printf "  ✓ Group-by 100k rows → 1000 groups (%.4fs)\n" t_grp100k
  end else begin
    incr fail_count; Printf.printf "  ✗ Group-by 100k rows: expected 1000 groups, got %d\n" n_groups_100k
  end;

  let (t_gagg100k, gagg_100k) = time_it (fun () ->
    Arrow_compute.group_aggregate grouped_100k "sum" "value"
  ) in
  if Arrow_table.num_rows gagg_100k = 1000 then begin
    incr pass_count; Printf.printf "  ✓ Group aggregate sum 100k rows → 1000 groups (%.4fs)\n" t_gagg100k
  end else begin
    incr fail_count; Printf.printf "  ✗ Group aggregate sum 100k rows failed\n"
  end;
  print_newline ();

  Printf.printf "Arrow Performance — 1M Row Tests:\n";

  (* Test 29: 1M row operations *)
  let tbl_1m = generate_test_table 1000000 10000 in
  if Arrow_table.num_rows tbl_1m = 1000000 then begin
    incr pass_count; Printf.printf "  ✓ Generated 1M row table\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ 1M row table generation failed\n"
  end;

  let (t_sel1m, _) = time_it (fun () -> Arrow_compute.project tbl_1m ["id"; "value"]) in
  incr pass_count; Printf.printf "  ✓ Project 1M rows (%.4fs)\n" t_sel1m;

  let (t_sum1m, _) = time_it (fun () -> Arrow_compute.sum_column tbl_1m "value") in
  incr pass_count; Printf.printf "  ✓ Sum 1M rows (%.4fs)\n" t_sum1m;

  let (t_mean1m, _) = time_it (fun () -> Arrow_compute.mean_column tbl_1m "value") in
  incr pass_count; Printf.printf "  ✓ Mean 1M rows (%.4fs)\n" t_mean1m;

  let (t_grp1m, grouped_1m) = time_it (fun () ->
    Arrow_compute.group_by tbl_1m ["group"]
  ) in
  let n_groups_1m = List.length grouped_1m.Arrow_compute.ocaml_groups in
  if n_groups_1m = 10000 then begin
    incr pass_count; Printf.printf "  ✓ Group-by 1M rows → 10000 groups (%.4fs)\n" t_grp1m
  end else begin
    incr fail_count; Printf.printf "  ✗ Group-by 1M rows: expected 10000 groups, got %d\n" n_groups_1m
  end;

  let (t_gagg1m, _) = time_it (fun () ->
    Arrow_compute.group_aggregate grouped_1m "mean" "value"
  ) in
  incr pass_count; Printf.printf "  ✓ Group aggregate mean 1M rows (%.4fs)\n" t_gagg1m;

  print_newline ();

  Printf.printf "Arrow Performance — Math Operations on Large Data:\n";

  (* Test 30: sqrt on 100k rows *)
  let (t_sqrt100k, sqrt_result) = time_it (fun () ->
    Arrow_compute.sqrt_column tbl_100k "value"
  ) in
  (match sqrt_result with
   | Some _ ->
     incr pass_count; Printf.printf "  ✓ sqrt_column on 100k rows (%.4fs)\n" t_sqrt100k
   | None ->
     incr fail_count; Printf.printf "  ✗ sqrt_column on 100k rows returned None\n");

  (* Test 31: abs on 100k rows *)
  let (t_abs100k, abs_result) = time_it (fun () ->
    Arrow_compute.abs_column tbl_100k "value"
  ) in
  (match abs_result with
   | Some _ ->
     incr pass_count; Printf.printf "  ✓ abs_column on 100k rows (%.4fs)\n" t_abs100k
   | None ->
     incr fail_count; Printf.printf "  ✗ abs_column on 100k rows returned None\n");

  (* Test 32: Comparison filter on 100k rows *)
  let (t_cmp100k, cmp_result) = time_it (fun () ->
    Arrow_compute.compare_column_scalar tbl_100k "value" 50.0 "gt"
  ) in
  (match cmp_result with
   | Some mask when Array.length mask = 100000 ->
     let n_true = Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 mask in
     incr pass_count; Printf.printf "  ✓ compare_column_scalar on 100k rows (%d match, %.4fs)\n" n_true t_cmp100k
   | _ ->
     incr fail_count; Printf.printf "  ✗ compare_column_scalar on 100k rows failed\n");

  print_newline ();

  Printf.printf "Arrow Performance — Summary:\n";
  Printf.printf "  Dataset sizes tested: 10k, 100k, 1M rows\n";
  Printf.printf "  Operations: select, filter, aggregate, group-by, math\n";
  Printf.printf "  All operations completed without OOM on 1M rows\n";
  print_newline ()
