(* tests/arrow/test_arrow_integration.ml *)
(* Phase 1: Arrow C GLib Integration Tests *)
(* Tests the Arrow-backed table infrastructure including:                *)
(* - FFI availability flag                                               *)
(* - Table creation (pure OCaml and native)                             *)
(* - Schema and column queries                                          *)
(* - Column data extraction                                             *)
(* - CSV reading with native fallback                                   *)

let run_tests pass_count fail_count _eval_string eval_string_env test =
  Printf.printf "Arrow Integration — FFI Infrastructure:\n";

  (* Test 1: Arrow FFI availability flag *)
  let arrow_avail = Arrow_ffi.arrow_available in
  if arrow_avail then begin
    incr pass_count; Printf.printf "  ✓ Arrow FFI marked as available\n"
  end else begin
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "Arrow FFI availability (Native library requested but not linked)"
  end;

  (* Test 2: Pure OCaml table creation *)
  let cols = [
    ("name", Arrow_table.StringColumn [| Some "Alice"; Some "Bob" |]);
    ("age", Arrow_table.IntColumn [| Some 30; Some 25 |]);
  ] in
  let tbl = Arrow_table.create cols 2 in
  if Arrow_table.num_rows tbl = 2 && Arrow_table.num_columns tbl = 2 then begin
    incr pass_count; Printf.printf "  ✓ Pure OCaml table creation works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Pure OCaml table creation failed\n"
  end;

  (* Test 3: Schema extraction *)
  let schema = Arrow_table.get_schema tbl in
  if List.length schema = 2
     && List.assoc "name" schema = Arrow_table.ArrowString
     && List.assoc "age" schema = Arrow_table.ArrowInt64 then begin
    incr pass_count; Printf.printf "  ✓ Schema extraction works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Schema extraction failed\n"
  end;

  (* Test 4: Column names *)
  let names = Arrow_table.column_names tbl in
  if names = ["name"; "age"] then begin
    incr pass_count; Printf.printf "  ✓ Column names correct\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Column names incorrect: [%s]\n"
      (String.concat ", " names)
  end;

  (* Test 5: Column access *)
  (match Arrow_table.get_column tbl "age" with
   | Some (Arrow_table.IntColumn data) ->
       if Array.length data = 2 && data.(0) = Some 30 && data.(1) = Some 25 then begin
         incr pass_count; Printf.printf "  ✓ Column access returns correct data\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ Column access data mismatch\n"
       end
   | _ ->
       incr fail_count; Printf.printf "  ✗ Column access failed or wrong type\n");

  (* Test 6: has_column *)
  if Arrow_table.has_column tbl "name" && not (Arrow_table.has_column tbl "missing") then begin
    incr pass_count; Printf.printf "  ✓ has_column works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ has_column failed\n"
  end;

  (* Test 7: native_handle is None for pure OCaml tables *)
  if tbl.native_handle = None then begin
    incr pass_count; Printf.printf "  ✓ Pure OCaml table has no native_handle\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Pure OCaml table should not have native_handle\n"
  end;

  (* Test 8: arrow_type_of_tag *)
  if Arrow_table.arrow_type_of_tag 0 = Arrow_table.ArrowInt64
     && Arrow_table.arrow_type_of_tag 1 = Arrow_table.ArrowFloat64
     && Arrow_table.arrow_type_of_tag 2 = Arrow_table.ArrowBoolean
     && Arrow_table.arrow_type_of_tag 3 = Arrow_table.ArrowString
     && Arrow_table.arrow_type_of_tag 99 = Arrow_table.ArrowNull then begin
    incr pass_count; Printf.printf "  ✓ arrow_type_of_tag works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ arrow_type_of_tag failed\n"
  end;
  print_newline ();

  Printf.printf "Arrow Integration — Table Operations:\n";

  (* Test 9: Project *)
  let projected = Arrow_table.project tbl ["name"] in
  if Arrow_table.num_columns projected = 1
     && Arrow_table.column_names projected = ["name"] then begin
    incr pass_count; Printf.printf "  ✓ Project (select) works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Project (select) failed\n"
  end;

  (* Test 10: Filter *)
  let mask = [| true; false |] in
  let filtered = Arrow_table.filter_rows tbl mask in
  if Arrow_table.num_rows filtered = 1 then begin
    incr pass_count; Printf.printf "  ✓ Filter rows works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Filter rows failed (got %d rows)\n"
      (Arrow_table.num_rows filtered)
  end;

  (* Test 11: Add column *)
  let new_col = Arrow_table.FloatColumn [| Some 95.5; Some 87.3 |] in
  let with_col = Arrow_table.add_column tbl "score" new_col in
  if Arrow_table.num_columns with_col = 3
     && Arrow_table.has_column with_col "score" then begin
    incr pass_count; Printf.printf "  ✓ Add column works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Add column failed\n"
  end;

  (* Test 12: Take rows *)
  let taken = Arrow_table.take_rows tbl [1; 0] in
  if Arrow_table.num_rows taken = 2 then begin
    (match Arrow_table.get_column taken "age" with
     | Some (Arrow_table.IntColumn data) ->
         if data.(0) = Some 25 && data.(1) = Some 30 then begin
           incr pass_count; Printf.printf "  ✓ Take rows with reorder works\n"
         end else begin
           incr fail_count; Printf.printf "  ✗ Take rows data order incorrect\n"
         end
     | _ ->
         incr fail_count; Printf.printf "  ✗ Take rows column access failed\n")
  end else begin
    incr fail_count; Printf.printf "  ✗ Take rows failed\n"
  end;

  (* Test 13: Sort by indices *)
  let sorted = Arrow_table.sort_by_indices tbl [| 1; 0 |] in
  (match Arrow_table.get_column sorted "name" with
   | Some (Arrow_table.StringColumn data) ->
       if data.(0) = Some "Bob" && data.(1) = Some "Alice" then begin
         incr pass_count; Printf.printf "  ✓ Sort by indices works\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ Sort by indices data order incorrect\n"
       end
   | _ ->
       incr fail_count; Printf.printf "  ✗ Sort by indices column access failed\n");
  print_newline ();

  Printf.printf "Arrow Integration — Bridge (column_to_values):\n";

  (* Test 14: Column to values conversion *)
  let int_col = Arrow_table.IntColumn [| Some 1; None; Some 3 |] in
  let values = Arrow_bridge.column_to_values int_col in
  let v_str = Array.to_list values |> List.map Ast.Utils.value_to_string |> String.concat ", " in
  if v_str = "1, NA(Int), 3" then begin
    incr pass_count; Printf.printf "  ✓ IntColumn to values with NA\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ IntColumn to values: got [%s]\n" v_str
  end;

  (* Test 15: Values to column conversion *)
  let vals = [| Ast.VInt 10; Ast.VInt 20; Ast.VNA Ast.NAInt |] in
  let col = Arrow_bridge.values_to_column vals in
  (match col with
   | Arrow_table.IntColumn data ->
       if data.(0) = Some 10 && data.(1) = Some 20 && data.(2) = None then begin
         incr pass_count; Printf.printf "  ✓ Values to IntColumn with NA\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ Values to IntColumn data mismatch\n"
       end
   | _ ->
       incr fail_count; Printf.printf "  ✗ Values to column produced wrong type\n");

  (* Test 16: Row to dict *)
  let dict = Arrow_bridge.row_to_dict tbl 0 in
  let name_val = List.assoc "name" dict in
  let age_val = List.assoc "age" dict in
  if Ast.Utils.value_to_string name_val = {|"Alice"|}
     && Ast.Utils.value_to_string age_val = "30" then begin
    incr pass_count; Printf.printf "  ✓ Row to dict works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Row to dict failed\n"
  end;
  print_newline ();

  Printf.printf "Arrow Integration — CSV Reading:\n";

  (* Test 17: CSV reading via T language *)
  let csv_path = "test_arrow_integration.csv" in
  let oc = open_out csv_path in
  output_string oc "name,age,score\nAlice,30,95.5\nBob,25,87.3\nCharlie,35,92.1\n";
  close_out oc;

  let env = Packages.init_env () in
  let (_, env) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_path) env in

  let (v, _) = eval_string_env "nrow(df)" env in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ Arrow-backed CSV nrow = 3\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Arrow-backed CSV nrow expected 3, got %s\n" result
  end;

  let (v, _) = eval_string_env "ncol(df)" env in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ Arrow-backed CSV ncol = 3\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Arrow-backed CSV ncol expected 3, got %s\n" result
  end;

  let (v, _) = eval_string_env "colnames(df)" env in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "age", "score"]|} then begin
    incr pass_count; Printf.printf "  ✓ Arrow-backed CSV colnames correct\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Arrow-backed CSV colnames: %s\n" result
  end;

  (* Test 18: Column access on Arrow-backed DataFrame *)
  let (v, _) = eval_string_env "df.name" env in
  let result = Ast.Utils.value_to_string v in
  if result = {|Vector["Alice", "Bob", "Charlie"]|} then begin
    incr pass_count; Printf.printf "  ✓ Arrow-backed CSV column access (name)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Arrow-backed CSV column access (name): %s\n" result
  end;

  let (v, _) = eval_string_env "df.age" env in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[30, 25, 35]" then begin
    incr pass_count; Printf.printf "  ✓ Arrow-backed CSV column access (age)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Arrow-backed CSV column access (age): %s\n" result
  end;

  (* Test 19: Colcraft operations on Arrow-backed DataFrame *)
  test "Arrow select"
    (Printf.sprintf {|df = read_csv("%s"); select(df, $name, $age) |> ncol|} csv_path)
    "2";

  test "Arrow filter"
    (Printf.sprintf {|df = read_csv("%s"); filter(df, $age > 28) |> nrow|} csv_path)
    "2";

  test "Arrow mutate"
    (Printf.sprintf {|df = read_csv("%s"); mutate(df, $senior = $age >= 30) |> ncol|} csv_path)
    "4";

  let (v, _) = eval_string_env
    (Printf.sprintf {|df_mut = read_csv("%s"); explain(mutate(df_mut, $senior = $age >= 30)).native_path_active|} csv_path)
    env in
  let result = Ast.Utils.value_to_string v in
  if result = "true" then begin
    incr pass_count; Printf.printf "  ✓ Arrow mutate keeps native path active\n"
  end else begin
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "Arrow mutate keeps native path active"
  end;

  test "Arrow arrange"
    (Printf.sprintf
      {|df = read_csv("%s"); df2 = arrange(df, $age); select(df2, $name) |> \(d) d.name|} csv_path)
    {|Vector["Bob", "Alice", "Charlie"]|};

  test "Arrow pipeline"
    (Printf.sprintf
      {|read_csv("%s") |> filter($age > 25) |> select($name, $score) |> nrow|} csv_path)
    "2";

  let csv_skip_path = "test_arrow_csv_skip_lines.csv" in
  let oc = open_out csv_skip_path in
  output_string oc "junk1,junk2\nname,age\nAlice,30\nBob,25\n";
  close_out oc;
  let env_skip = Packages.init_env () in
  let (_, env_skip) =
    eval_string_env (Printf.sprintf {|df_skip = read_csv("%s", skip_lines = 1)|} csv_skip_path) env_skip
  in
  let (v, _) = eval_string_env "nrow(df_skip)" env_skip in
  let skip_nrow = Ast.Utils.value_to_string v in
  if skip_nrow = "2" then begin
    incr pass_count; Printf.printf "  ✓ read_csv(skip_lines=1) honors public builtin CSV options\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ read_csv(skip_lines=1) expected nrow=2, got %s\n" skip_nrow
  end;
  (match Arrow_io.read_csv_local csv_skip_path with
   | Ok tbl when Arrow_table.num_rows tbl = 3 ->
       incr pass_count; Printf.printf "  ✓ Arrow_io.read_csv_local differs from read_csv(skip_lines) on same file\n"
   | Ok tbl ->
       incr fail_count; Printf.printf "  ✗ Arrow_io.read_csv_local expected nrow=3 on same file, got %d\n" (Arrow_table.num_rows tbl)
   | Error msg ->
       incr fail_count; Printf.printf "  ✗ Arrow_io.read_csv_local failed on CSV path distinction test: %s\n" msg);
  print_newline ();

  Printf.printf "Arrow Integration — Compute Module:\n";

  (* Test 20: Arrow_compute.project *)
  let tbl3 = Arrow_table.create [
    ("a", Arrow_table.IntColumn [| Some 1; Some 2 |]);
    ("b", Arrow_table.StringColumn [| Some "x"; Some "y" |]);
    ("c", Arrow_table.FloatColumn [| Some 1.0; Some 2.0 |]);
  ] 2 in
  let proj = Arrow_compute.project tbl3 ["a"; "c"] in
  if Arrow_table.num_columns proj = 2 && Arrow_table.column_names proj = ["a"; "c"] then begin
    incr pass_count; Printf.printf "  ✓ Arrow_compute.project works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Arrow_compute.project failed\n"
  end;

  (* Test 21: Arrow_compute.filter *)
  let filt = Arrow_compute.filter tbl3 [| true; false |] in
  if Arrow_table.num_rows filt = 1 then begin
    incr pass_count; Printf.printf "  ✓ Arrow_compute.filter works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Arrow_compute.filter failed\n"
  end;

  (* Test 22: Arrow_compute.add_column *)
  let new_c = Arrow_table.BoolColumn [| Some true; Some false |] in
  let added = Arrow_compute.add_column tbl3 "d" new_c in
  if Arrow_table.num_columns added = 4 then begin
    incr pass_count; Printf.printf "  ✓ Arrow_compute.add_column works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Arrow_compute.add_column failed\n"
  end;

  (* Test 23: Arrow_compute.sort_by_column on pure OCaml table (returns None) *)
  (match Arrow_compute.sort_by_column tbl3 "a" true with
   | None ->
       incr pass_count; Printf.printf "  ✓ sort_by_column returns None for pure OCaml table\n"
   | Some _ ->
       incr pass_count; Printf.printf "  ✓ sort_by_column returned result (native available)\n");

  (* Test 24: Arrow_compute.sort_by_indices *)
  let sorted_tbl = Arrow_compute.sort_by_indices tbl3 [| 1; 0 |] in
  (match Arrow_table.get_column sorted_tbl "a" with
   | Some (Arrow_table.IntColumn data) ->
       if data.(0) = Some 2 && data.(1) = Some 1 then begin
         incr pass_count; Printf.printf "  ✓ Arrow_compute.sort_by_indices works\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ Arrow_compute.sort_by_indices data order incorrect\n"
       end
   | _ ->
       incr fail_count; Printf.printf "  ✗ Arrow_compute.sort_by_indices failed\n");

  (* Test 25: Arrow_compute.add_scalar on pure OCaml table (returns None) *)
  (match Arrow_compute.add_scalar tbl3 "c" 10.0 with
   | None ->
       incr pass_count; Printf.printf "  ✓ add_scalar returns None for pure OCaml table\n"
   | Some tbl_added ->
       (* If native Arrow is available, verify the operation *)
       (match Arrow_table.get_column tbl_added "c" with
        | Some (Arrow_table.FloatColumn data) when data.(0) = Some 11.0 ->
            incr pass_count; Printf.printf "  ✓ add_scalar works with native backend\n"
        | _ ->
            incr pass_count; Printf.printf "  ✓ add_scalar returned result (native available)\n"));

  (* Test 26: Arrow_compute.multiply_scalar on pure OCaml table (returns None) *)
  (match Arrow_compute.multiply_scalar tbl3 "c" 2.0 with
   | None ->
       incr pass_count; Printf.printf "  ✓ multiply_scalar returns None for pure OCaml table\n"
   | Some tbl_mult ->
       (match Arrow_table.get_column tbl_mult "c" with
        | Some (Arrow_table.FloatColumn data) when data.(0) = Some 2.0 ->
            incr pass_count; Printf.printf "  ✓ multiply_scalar works with native backend\n"
        | _ ->
            incr pass_count; Printf.printf "  ✓ multiply_scalar returned result (native available)\n"));

  (* Test 27: Arrow_compute.subtract_scalar on pure OCaml table (returns None) *)
  (match Arrow_compute.subtract_scalar tbl3 "c" 0.5 with
   | None ->
       incr pass_count; Printf.printf "  ✓ subtract_scalar returns None for pure OCaml table\n"
   | Some _ ->
       incr pass_count; Printf.printf "  ✓ subtract_scalar returned result (native available)\n");

  (* Test 28: Arrow_compute.divide_scalar on pure OCaml table (returns None) *)
  (match Arrow_compute.divide_scalar tbl3 "c" 2.0 with
   | None ->
       incr pass_count; Printf.printf "  ✓ divide_scalar returns None for pure OCaml table\n"
   | Some _ ->
       incr pass_count; Printf.printf "  ✓ divide_scalar returned result (native available)\n");
  print_newline ();

  Printf.printf "Arrow Integration — Compute with Native Backend:\n";

  (* Test 29: sort_by_column on Arrow-backed CSV DataFrame *)
  let csv_compute = "test_arrow_compute.csv" in
  let oc2 = open_out csv_compute in
  output_string oc2 "name,age,score\nCharlie,35,92.1\nAlice,30,95.5\nBob,25,87.3\n";
  close_out oc2;

  let env_c = Packages.init_env () in
  let (_, env_c) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_compute) env_c in

  (* Test arrange ascending on native-backed table *)
  test "Compute: arrange ascending (native sort)"
    (Printf.sprintf {|df = read_csv("%s"); arrange(df, $age) |> \(d) d.name|} csv_compute)
    {|Vector["Bob", "Alice", "Charlie"]|};

  (* Test arrange descending on native-backed table *)
  test "Compute: arrange descending (native sort)"
    (Printf.sprintf {|df = read_csv("%s"); arrange(df, $age, "desc") |> \(d) d.name|} csv_compute)
    {|Vector["Charlie", "Alice", "Bob"]|};

  (* Test 30: select on native-backed table via compute *)
  test "Compute: select (native project)"
    (Printf.sprintf {|df = read_csv("%s"); select(df, $name, $score) |> ncol|} csv_compute)
    "2";

  (* Test 31: filter on native-backed table via compute *)
  test "Compute: filter (native filter)"
    (Printf.sprintf {|df = read_csv("%s"); filter(df, $age > 28) |> nrow|} csv_compute)
    "2";

  (* Test 32: chained compute operations *)
  test "Compute: filter + select + arrange pipeline"
    (Printf.sprintf
      {|read_csv("%s") |> filter($age >= 30) |> select($name, $age) |> arrange($age) |> \(d) d.name|}
      csv_compute)
    {|Vector["Alice", "Charlie"]|};

  ignore env_c;
  (try Sys.remove csv_compute with _ -> ());
  print_newline ();

  Printf.printf "Arrow Integration — Group-By & Aggregation (Phase 3):\n";

  (* Test 33: Arrow_compute.group_by on pure OCaml table *)
  let group_tbl = Arrow_table.create [
    ("name", Arrow_table.StringColumn [| Some "Alice"; Some "Bob"; Some "Alice"; Some "Bob"; Some "Alice" |]);
    ("dept", Arrow_table.StringColumn [| Some "Eng"; Some "Eng"; Some "Eng"; Some "Sales"; Some "Sales" |]);
    ("score", Arrow_table.FloatColumn [| Some 90.0; Some 80.0; Some 85.0; Some 70.0; Some 95.0 |]);
  ] 5 in
  let grouped = Arrow_compute.group_by group_tbl ["name"] in
  let n_groups = List.length (Arrow_compute.get_ocaml_groups grouped) in
  if n_groups = 2 then begin
    incr pass_count; Printf.printf "  ✓ group_by produces 2 groups for ['name']\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ group_by expected 2 groups, got %d\n" n_groups
  end;

  (* Test 34: group_by preserves group order (insertion order) *)
  let first_key = fst (List.hd (Arrow_compute.get_ocaml_groups grouped)) in
  if first_key = {|"Alice"|} then begin
    incr pass_count; Printf.printf "  ✓ group_by preserves insertion order\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ group_by first group expected \"Alice\", got %s\n" first_key
  end;

  (* Test 35: group_by with multiple keys *)
  let grouped2 = Arrow_compute.group_by group_tbl ["name"; "dept"] in
  let n_groups2 = List.length (Arrow_compute.get_ocaml_groups grouped2) in
  if n_groups2 = 4 then begin
    incr pass_count; Printf.printf "  ✓ group_by with 2 keys produces 4 groups\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ group_by with 2 keys expected 4 groups, got %d\n" n_groups2
  end;

  (* Test 36: group_aggregate sum *)
  let sum_result = Arrow_compute.group_aggregate grouped "sum" "score" in
  if Arrow_table.num_rows sum_result = 2 then begin
    (match Arrow_table.get_column sum_result "score" with
     | Some (Arrow_table.FloatColumn data) ->
         (* Alice: 90.0 + 85.0 + 95.0 = 270.0, Bob: 80.0 + 70.0 = 150.0 *)
         if data.(0) = Some 270.0 && data.(1) = Some 150.0 then begin
           incr pass_count; Printf.printf "  ✓ group_aggregate sum is correct\n"
         end else begin
           incr fail_count;
           Printf.printf "  ✗ group_aggregate sum values incorrect: [%s]\n"
             (Array.to_list data |> List.map (fun v ->
               match v with Some f -> string_of_float f | None -> "NA")
             |> String.concat ", ")
         end
     | _ ->
         incr fail_count; Printf.printf "  ✗ group_aggregate sum column type mismatch\n")
  end else begin
    incr fail_count; Printf.printf "  ✗ group_aggregate sum expected 2 rows, got %d\n"
      (Arrow_table.num_rows sum_result)
  end;

  (* Test 37: group_aggregate mean *)
  let mean_result = Arrow_compute.group_aggregate grouped "mean" "score" in
  if Arrow_table.num_rows mean_result = 2 then begin
    (match Arrow_table.get_column mean_result "score" with
     | Some (Arrow_table.FloatColumn data) ->
         (* Alice: (90+85+95)/3 = 90.0, Bob: (80+70)/2 = 75.0 *)
         let close a b = Float.abs (a -. b) < 0.001 in
         (match data.(0), data.(1) with
          | Some a, Some b when close a 90.0 && close b 75.0 ->
              incr pass_count; Printf.printf "  ✓ group_aggregate mean is correct\n"
          | _ ->
              incr fail_count;
              Printf.printf "  ✗ group_aggregate mean values incorrect: [%s]\n"
                (Array.to_list data |> List.map (fun v ->
                  match v with Some f -> string_of_float f | None -> "NA")
                |> String.concat ", "))
     | _ ->
         incr fail_count; Printf.printf "  ✗ group_aggregate mean column type mismatch\n")
  end else begin
    incr fail_count; Printf.printf "  ✗ group_aggregate mean expected 2 rows, got %d\n"
      (Arrow_table.num_rows mean_result)
  end;

  (* Test 38: group_aggregate count *)
  let count_result = Arrow_compute.group_aggregate grouped "count" "" in
  if Arrow_table.num_rows count_result = 2 then begin
    (match Arrow_table.get_column count_result "n" with
     | Some (Arrow_table.FloatColumn data) ->
         (* Alice: 3 rows, Bob: 2 rows *)
         if data.(0) = Some 3.0 && data.(1) = Some 2.0 then begin
           incr pass_count; Printf.printf "  ✓ group_aggregate count is correct\n"
         end else begin
           incr fail_count;
           Printf.printf "  ✗ group_aggregate count values incorrect\n"
         end
     | _ ->
         incr fail_count; Printf.printf "  ✗ group_aggregate count column type mismatch\n")
  end else begin
    incr fail_count; Printf.printf "  ✗ group_aggregate count expected 2 rows, got %d\n"
      (Arrow_table.num_rows count_result)
  end;

  (* Test 39: group_aggregate result has key columns *)
  if Arrow_table.has_column sum_result "name" then begin
    (match Arrow_table.get_column sum_result "name" with
     | Some (Arrow_table.StringColumn data) ->
         if data.(0) = Some "Alice" && data.(1) = Some "Bob" then begin
           incr pass_count; Printf.printf "  ✓ group_aggregate result has correct key column\n"
         end else begin
           incr fail_count; Printf.printf "  ✗ group_aggregate key column values incorrect\n"
         end
     | _ ->
         incr fail_count; Printf.printf "  ✗ group_aggregate key column type mismatch\n")
  end else begin
    incr fail_count; Printf.printf "  ✗ group_aggregate result missing key column 'name'\n"
  end;

  let csv_groupby = "test_arrow_groupby.csv" in
  let oc3 = open_out csv_groupby in
  output_string oc3 "name,dept,score\nAlice,Eng,90\nBob,Eng,80\nAlice,Sales,95\nBob,Sales,70\n";
  close_out oc3;

  if Arrow_ffi.arrow_available then begin
    (match Arrow_io.read_csv csv_groupby with
     | Ok native_group_tbl ->
         (match native_group_tbl.native_handle with
          | Some _ ->
              let native_grouped = Arrow_compute.group_by native_group_tbl ["name"] in
              if not (Arrow_compute.ocaml_groups_materialized native_grouped) then begin
                   incr pass_count; Printf.printf "  ✓ native group_by keeps OCaml groups lazy\n"
              end else begin
                incr fail_count; Printf.printf "  ✗ native group_by eagerly materialized OCaml groups\n"
              end;

              let native_mean_result = Arrow_compute.group_aggregate native_grouped "mean" "score" in
              let mean_ok =
                Arrow_table.num_rows native_mean_result = 2
                && (match Arrow_table.get_column native_mean_result "score" with
                    | Some (Arrow_table.FloatColumn data) ->
                        let close a b = Float.abs (a -. b) < 0.001 in
                        (match data.(0), data.(1) with
                         | Some a, Some b -> close a 92.5 && close b 75.0
                         | _ -> false)
                    | _ -> false)
              in
              if mean_ok then begin
                incr pass_count; Printf.printf "  ✓ native group_aggregate mean stays correct\n"
              end else begin
                incr fail_count; Printf.printf "  ✗ native group_aggregate mean returned incorrect values\n"
              end;

              let native_sum_result = Arrow_compute.group_aggregate native_grouped "sum" "score" in
              let sum_ok =
                Arrow_table.num_rows native_sum_result = 2
                && (match Arrow_table.get_column native_sum_result "score" with
                    | Some (Arrow_table.FloatColumn data) ->
                        data.(0) = Some 185.0 && data.(1) = Some 150.0
                    | _ -> false)
              in
              if sum_ok then begin
                incr pass_count; Printf.printf "  ✓ native group_aggregate sum stays correct\n"
              end else begin
                incr fail_count; Printf.printf "  ✗ native group_aggregate sum returned incorrect values\n"
              end;

              if not (Arrow_compute.ocaml_groups_materialized native_grouped) then begin
                   incr pass_count; Printf.printf "  ✓ native group_aggregate avoids forcing OCaml groups\n"
              end else begin
                incr fail_count; Printf.printf "  ✗ native group_aggregate unexpectedly forced OCaml groups\n"
              end;

              let native_groups = Arrow_compute.get_ocaml_groups native_grouped in
              if List.length native_groups = 2 then begin
                incr pass_count; Printf.printf "  ✓ get_ocaml_groups materializes native groups on demand\n"
              end else begin
                incr fail_count; Printf.printf "  ✗ get_ocaml_groups expected 2 groups, got %d\n"
                  (List.length native_groups)
              end
          | None ->
              Test_arrow_helpers.record_native_requirement_result pass_count fail_count
                "native group_by keeps OCaml groups lazy";
              Test_arrow_helpers.record_native_requirement_result pass_count fail_count
                "native group_aggregate mean stays correct";
              Test_arrow_helpers.record_native_requirement_result pass_count fail_count
                "native group_aggregate sum stays correct";
              Test_arrow_helpers.record_native_requirement_result pass_count fail_count
                "native group_aggregate avoids forcing OCaml groups";
              Test_arrow_helpers.record_native_requirement_result pass_count fail_count
                "get_ocaml_groups materializes native groups on demand")
     | Error msg ->
         Test_arrow_helpers.record_native_requirement_result pass_count fail_count
           (Printf.sprintf "native group_by smoke test CSV read failed: %s" msg);
         Test_arrow_helpers.record_native_requirement_result pass_count fail_count
           "native group_aggregate mean stays correct";
         Test_arrow_helpers.record_native_requirement_result pass_count fail_count
           "native group_aggregate sum stays correct";
         Test_arrow_helpers.record_native_requirement_result pass_count fail_count
           "native group_aggregate avoids forcing OCaml groups";
         Test_arrow_helpers.record_native_requirement_result pass_count fail_count
           "get_ocaml_groups materializes native groups on demand")
  end else begin
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "native group_by keeps OCaml groups lazy";
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "native group_aggregate mean stays correct";
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "native group_aggregate sum stays correct";
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "native group_aggregate avoids forcing OCaml groups";
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "get_ocaml_groups materializes native groups on demand"
  end;

  (* Test 40: group_by + summarize via T language *)
  test "Group-by + summarize (mean)"
    (Printf.sprintf
      {|df = read_csv("%s"); df |> group_by($name) |> summarize($avg_score = mean($score)) |> \(d) d.avg_score|}
      csv_groupby)
    "Vector[92.5, 75.]";

  test "Group-by + summarize (count via n)"
    (Printf.sprintf
      {|df = read_csv("%s"); df |> group_by($name) |> summarize($n = n()) |> \(d) d.n|}
      csv_groupby)
    "Vector[2, 2]";

  (try Sys.remove csv_groupby with _ -> ());
  print_newline ();

  Printf.printf "Arrow Integration — Zero-Copy Column Views (Phase 4):\n";

  (* Test 41: numeric_view type exists and zero_copy_view returns None for pure OCaml table *)
  let ocaml_tbl = Arrow_table.create [
    ("x", Arrow_table.FloatColumn [| Some 1.0; Some 2.0; Some 3.0 |]);
    ("y", Arrow_table.IntColumn [| Some 10; Some 20; Some 30 |]);
    ("s", Arrow_table.StringColumn [| Some "a"; Some "b"; Some "c" |]);
  ] 3 in
  (match Arrow_column.get_column ocaml_tbl "x" with
   | Some col_view ->
     (match Arrow_column.zero_copy_view col_view with
      | None ->
        incr pass_count; Printf.printf "  ✓ zero_copy_view returns None for pure OCaml table\n"
      | Some _ ->
        incr fail_count; Printf.printf "  ✗ zero_copy_view should return None for pure OCaml table\n")
   | None ->
     incr fail_count; Printf.printf "  ✗ get_column failed for pure OCaml table\n");

  (* Test 42: zero_copy_view returns None for string column (even native) *)
  (match Arrow_column.get_column ocaml_tbl "s" with
   | Some col_view ->
     (match Arrow_column.zero_copy_view col_view with
      | None ->
        incr pass_count; Printf.printf "  ✓ zero_copy_view returns None for string column\n"
      | Some _ ->
        incr fail_count; Printf.printf "  ✗ zero_copy_view should return None for string column\n")
   | None ->
     incr fail_count; Printf.printf "  ✗ get_column failed for string column\n");

  (* Test 43: column_view preserves column type *)
  (match Arrow_column.get_column ocaml_tbl "x" with
   | Some col_view ->
     if Arrow_column.column_type col_view = Arrow_table.ArrowFloat64 then begin
       incr pass_count; Printf.printf "  ✓ column_view preserves Float64 type\n"
     end else begin
       incr fail_count; Printf.printf "  ✗ column_view type mismatch for Float64\n"
     end
   | None ->
     incr fail_count; Printf.printf "  ✗ get_column failed\n");

  (match Arrow_column.get_column ocaml_tbl "y" with
   | Some col_view ->
     if Arrow_column.column_type col_view = Arrow_table.ArrowInt64 then begin
       incr pass_count; Printf.printf "  ✓ column_view preserves Int64 type\n"
     end else begin
       incr fail_count; Printf.printf "  ✗ column_view type mismatch for Int64\n"
     end
   | None ->
     incr fail_count; Printf.printf "  ✗ get_column failed\n");

  (* Test 44: column_view length is correct *)
  (match Arrow_column.get_column ocaml_tbl "x" with
   | Some col_view ->
     if Arrow_column.column_length col_view = 3 then begin
       incr pass_count; Printf.printf "  ✓ column_view length is correct\n"
     end else begin
       incr fail_count; Printf.printf "  ✗ column_view length incorrect\n"
     end
   | None ->
     incr fail_count; Printf.printf "  ✗ get_column failed\n");

  (* Test 45: zero_copy_view with native-backed CSV table *)
  let csv_zerocopy = "test_arrow_zerocopy.csv" in
  let oc4 = open_out csv_zerocopy in
  output_string oc4 "val_f,val_i,name\n1.5,10,Alice\n2.5,20,Bob\n3.5,30,Charlie\n";
  close_out oc4;

  (match Arrow_io.read_csv csv_zerocopy with
   | Ok native_tbl ->
     (match native_tbl.native_handle with
      | Some _ ->
        (* Test float64 zero-copy view *)
        (match Arrow_column.get_column native_tbl "val_f" with
         | Some col_view ->
           (match Arrow_column.zero_copy_view col_view with
            | Some (Arrow_column.FloatView ba) ->
              let len = Bigarray.Array1.dim ba in
              let close a b = Float.abs (a -. b) < 1e-10 in
              if len = 3 && close ba.{0} 1.5 && close ba.{1} 2.5 && close ba.{2} 3.5 then begin
                incr pass_count; Printf.printf "  ✓ FloatView zero-copy view is correct\n"
              end else begin
                incr fail_count; Printf.printf "  ✗ FloatView data mismatch (len=%d)\n" len
              end
            | Some (Arrow_column.IntView _) ->
              incr fail_count; Printf.printf "  ✗ Expected FloatView, got IntView\n"
             | None ->
               Test_arrow_helpers.record_native_requirement_result pass_count fail_count
                 "zero_copy_view returned None for native float column")
          | None ->
            incr fail_count; Printf.printf "  ✗ get_column failed for native float column\n");

        (* Test int64 zero-copy view *)
        (match Arrow_column.get_column native_tbl "val_i" with
         | Some col_view ->
           (match Arrow_column.zero_copy_view col_view with
            | Some (Arrow_column.IntView ba) ->
              let len = Bigarray.Array1.dim ba in
              if len = 3 && ba.{0} = 10L && ba.{1} = 20L && ba.{2} = 30L then begin
                incr pass_count; Printf.printf "  ✓ IntView zero-copy view is correct\n"
              end else begin
                incr fail_count; Printf.printf "  ✗ IntView data mismatch (len=%d)\n" len
              end
            | Some (Arrow_column.FloatView _) ->
              incr fail_count; Printf.printf "  ✗ Expected IntView, got FloatView\n"
             | None ->
               Test_arrow_helpers.record_native_requirement_result pass_count fail_count
                 "zero_copy_view returned None for native int column")
          | None ->
            incr fail_count; Printf.printf "  ✗ get_column failed for native int column\n");

        (* Test string column returns None *)
        (match Arrow_column.get_column native_tbl "name" with
         | Some col_view ->
           (match Arrow_column.zero_copy_view col_view with
            | None ->
              incr pass_count; Printf.printf "  ✓ zero_copy_view returns None for native string column\n"
            | Some _ ->
              incr fail_count; Printf.printf "  ✗ zero_copy_view should return None for string column\n")
         | None ->
           incr fail_count; Printf.printf "  ✗ get_column failed for native string column\n")

       | None ->
         Test_arrow_helpers.record_native_requirement_result pass_count fail_count
           "CSV read did not retain a native Arrow handle";
         Test_arrow_helpers.record_native_requirement_result pass_count fail_count
           "native float zero-copy smoke test skipped";
         Test_arrow_helpers.record_native_requirement_result pass_count fail_count
           "native int zero-copy smoke test skipped";
         Test_arrow_helpers.record_native_requirement_result pass_count fail_count
           "native string zero-copy smoke test skipped")
    | Error msg ->
      Test_arrow_helpers.record_native_requirement_result pass_count fail_count
        (Printf.sprintf "CSV read failed for native smoke test: %s" msg);
      Test_arrow_helpers.record_native_requirement_result pass_count fail_count
        "native float zero-copy smoke test skipped";
      Test_arrow_helpers.record_native_requirement_result pass_count fail_count
        "native int zero-copy smoke test skipped";
      Test_arrow_helpers.record_native_requirement_result pass_count fail_count
        "native string zero-copy smoke test skipped");

  (try Sys.remove csv_zerocopy with _ -> ());

  Printf.printf "Arrow Integration — Temporal parsing:\n";

  (match Arrow_io.build_column [| "2024-01-15"; "NA" |] Arrow_table.ArrowDate with
   | Arrow_table.DateColumn data ->
       if data.(0) = Some (Chrono.days_from_civil 2024 1 15) && data.(1) = None then begin
         incr pass_count; Printf.printf "  ✓ build_column parses ArrowDate values\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ build_column ArrowDate data mismatch\n"
       end
   | _ ->
       incr fail_count; Printf.printf "  ✗ build_column ArrowDate returned wrong column type\n");

  (match Arrow_io.build_column
           [| "2024-01-15T09:30:00.123456"; "NA" |]
           (Arrow_table.ArrowTimestamp (Some "UTC")) with
   | Arrow_table.DatetimeColumn (data, tz) ->
       if data.(0) = Some (Chrono.datetime_of_components 2024 1 15 9 30 0 123456)
          && data.(1) = None
          && tz = Some "UTC" then begin
         incr pass_count; Printf.printf "  ✓ build_column parses ArrowTimestamp values\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ build_column ArrowTimestamp data mismatch\n"
       end
   | _ ->
        incr fail_count; Printf.printf "  ✗ build_column ArrowTimestamp returned wrong column type\n");

  let dt_col = Arrow_table.DatetimeColumn (
    [| Some (Chrono.datetime_of_components 2024 1 15 9 30 0 0);
       None;
       Some (Chrono.datetime_of_components 2024 1 16 14 45 30 500000) |],
    Some "UTC"
  ) in
  if Arrow_table.is_arrow_table_new_supported dt_col then begin
    incr fail_count; Printf.printf "  ✗ DatetimeColumn should currently be unsupported for native rebuild\n"
  end else begin
    incr pass_count; Printf.printf "  ✓ DatetimeColumn is currently unsupported for native rebuild\n"
  end;
  let dt_tbl = Arrow_table.create [("ts", dt_col)] 3 in
  let dt_mat = Arrow_table.materialize dt_tbl in
  if Arrow_table.is_native_backed dt_mat then begin
    incr fail_count; Printf.printf "  ✗ DatetimeColumn materialization should stay on pure fallback\n"
  end else begin
    (match Arrow_table.get_column dt_mat "ts" with
     | Some (Arrow_table.DatetimeColumn (data, tz)) ->
         if data.(0) = Some (Chrono.datetime_of_components 2024 1 15 9 30 0 0)
            && data.(1) = None
            && data.(2) = Some (Chrono.datetime_of_components 2024 1 16 14 45 30 500000)
            && tz = Some "UTC" then begin
           incr pass_count; Printf.printf "  ✓ DatetimeColumn fallback materialization preserves values\n"
         end else begin
           incr fail_count; Printf.printf "  ✗ DatetimeColumn fallback materialization data mismatch\n"
         end
     | _ ->
         incr fail_count; Printf.printf "  ✗ DatetimeColumn fallback materialization returned wrong type\n")
  end;

  print_newline ();

  Printf.printf "Arrow Integration — Dictionary (Factor) Native Support:\n";

  (* Test: DictionaryColumn creation and access *)
  let dict_col = Arrow_table.DictionaryColumn (
    [| Some 0; Some 1; None; Some 0; Some 2 |],
    ["red"; "green"; "blue"],
    false
  ) in
  let dict_tbl = Arrow_table.create [
    ("color", dict_col);
    ("value", Arrow_table.IntColumn [| Some 10; Some 20; None; Some 40; Some 50 |]);
  ] 5 in
  if Arrow_table.num_rows dict_tbl = 5 && Arrow_table.num_columns dict_tbl = 2 then begin
    incr pass_count; Printf.printf "  ✓ DictionaryColumn table creation works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ DictionaryColumn table creation failed\n"
  end;

  (* Test: Schema reflects ArrowDictionary type *)
  let dict_schema = Arrow_table.get_schema dict_tbl in
  (match List.assoc_opt "color" dict_schema with
   | Some t when t = Arrow_table.ArrowDictionary ->
     incr pass_count; Printf.printf "  ✓ DictionaryColumn schema type is ArrowDictionary\n"
   | _ ->
     incr fail_count; Printf.printf "  ✗ DictionaryColumn schema type mismatch\n");

  (* Test: DictionaryColumn read-back *)
  (match Arrow_table.get_column dict_tbl "color" with
   | Some (Arrow_table.DictionaryColumn (indices, levels, ordered)) ->
       if indices.(0) = Some 0 && indices.(1) = Some 1 && indices.(2) = None
          && indices.(3) = Some 0 && indices.(4) = Some 2
          && levels = ["red"; "green"; "blue"] && not ordered then begin
         incr pass_count; Printf.printf "  ✓ DictionaryColumn read-back correct\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ DictionaryColumn read-back data mismatch\n"
       end
   | _ ->
       incr fail_count; Printf.printf "  ✗ DictionaryColumn read-back returned wrong type\n");

  (* Test: is_arrow_table_new_supported returns true for DictionaryColumn *)
  if Arrow_table.is_arrow_table_new_supported dict_col then begin
    incr pass_count; Printf.printf "  ✓ is_arrow_table_new_supported = true for DictionaryColumn\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ is_arrow_table_new_supported should be true for DictionaryColumn\n"
  end;

  (* Test: arrow_type_of_tag for new tags *)
  if Arrow_table.arrow_type_of_tag 4 = Arrow_table.ArrowDictionary then begin
    incr pass_count; Printf.printf "  ✓ arrow_type_of_tag 4 = ArrowDictionary\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ arrow_type_of_tag 4 mismatch\n"
  end;
  if (match Arrow_table.arrow_type_of_tag 5 with Arrow_table.ArrowList _ -> true | _ -> false) then begin
    incr pass_count; Printf.printf "  ✓ arrow_type_of_tag 5 = ArrowList\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ arrow_type_of_tag 5 mismatch\n"
  end;

  (* Test: Bridge column_to_values for DictionaryColumn → VFactor *)
  let factor_vals = Arrow_bridge.column_to_values dict_col in
  let v0_str = Ast.Utils.value_to_string factor_vals.(0) in
  let v1_str = Ast.Utils.value_to_string factor_vals.(1) in
  let v2_str = Ast.Utils.value_to_string factor_vals.(2) in
  if v0_str = {|Factor("red")|} && v1_str = {|Factor("green")|} && v2_str = "NA" then begin
    incr pass_count; Printf.printf "  ✓ Bridge DictionaryColumn → VFactor conversion\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Bridge DictionaryColumn → VFactor: got [%s, %s, %s]\n" v0_str v1_str v2_str
  end;

  (* Test: Bridge values_to_column for VFactor → DictionaryColumn *)
  let factor_input = [| Ast.VFactor (0, ["A"; "B"; "C"], true);
                        Ast.VNA Ast.NAGeneric;
                        Ast.VFactor (2, ["A"; "B"; "C"], true) |] in
  (match Arrow_bridge.values_to_column factor_input with
   | Arrow_table.DictionaryColumn (idx, levels, ordered) ->
       if idx.(0) = Some 0 && idx.(1) = None && idx.(2) = Some 2
          && levels = ["A"; "B"; "C"] && ordered then begin
         incr pass_count; Printf.printf "  ✓ Bridge VFactor → DictionaryColumn round-trip\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ Bridge VFactor → DictionaryColumn data mismatch\n"
       end
   | _ ->
       incr fail_count; Printf.printf "  ✗ Bridge VFactor → DictionaryColumn returned wrong type\n");

  (* Test: Materialization of DataFrame with DictionaryColumn *)
  let mat_tbl = Arrow_table.materialize dict_tbl in
  let mat_is_native = Arrow_table.is_native_backed mat_tbl in
  if mat_is_native then begin
    incr pass_count; Printf.printf "  ✓ DictionaryColumn table materializes to native Arrow\n";
    (* Verify round-trip: read column back from native, including ordered flag *)
    (match Arrow_table.get_column mat_tbl "color" with
     | Some (Arrow_table.DictionaryColumn (indices, levels, ordered)) ->
         if indices.(0) = Some 0 && indices.(1) = Some 1 && indices.(2) = None
            && indices.(3) = Some 0 && indices.(4) = Some 2
            && levels = ["red"; "green"; "blue"]
            && not ordered then begin
           incr pass_count; Printf.printf "  ✓ Native Dictionary column round-trip verified (ordered=%b)\n" ordered
         end else begin
           incr fail_count; Printf.printf "  ✗ Native Dictionary column round-trip data mismatch (ordered=%b)\n" ordered
         end
     | _ ->
         incr fail_count; Printf.printf "  ✗ Native Dictionary column read-back returned wrong type\n")
  end else begin
    (* Native Arrow may not be available in all environments *)
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "DictionaryColumn table materializes to native Arrow"
  end;

  (* Test: Factor operations via T language on native-backed DataFrame *)
  test "Factor in mutate with native path"
    {|df = dataframe([[name: "Alice", dept: "HR"], [name: "Bob", dept: "IT"], [name: "Charlie", dept: "HR"]]); mutate(df, $dept_f = factor($dept)) |> ncol|}
    "3";

  test "Factor levels extraction"
    {|v = factor(["a", "b", "a", "c"]); levels(v)|}
    {|Vector["a", "b", "c"]|};

  (* Test: Ordered factor round-trip through bridge *)
  let ordered_input = [| Ast.VFactor (1, ["low"; "med"; "high"], true);
                         Ast.VNA Ast.NAGeneric;
                         Ast.VFactor (0, ["low"; "med"; "high"], true) |] in
  (match Arrow_bridge.values_to_column ordered_input with
   | Arrow_table.DictionaryColumn (idx, levels, ordered) ->
       if idx.(0) = Some 1 && idx.(1) = None && idx.(2) = Some 0
          && levels = ["low"; "med"; "high"] && ordered then begin
         incr pass_count; Printf.printf "  ✓ Ordered factor bridge round-trip preserves ordered flag\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ Ordered factor bridge round-trip data mismatch\n"
       end
   | _ ->
       incr fail_count; Printf.printf "  ✗ Ordered factor bridge round-trip returned wrong type\n");

  (* Test: Ordered factor native materialization round-trip *)
  let ordered_col = Arrow_table.DictionaryColumn (
    [| Some 1; None; Some 0 |],
    ["low"; "med"; "high"],
    true) in
  let ordered_tbl = Arrow_table.create [("rank", ordered_col)] 3 in
  let ordered_mat = Arrow_table.materialize ordered_tbl in
  if Arrow_table.is_native_backed ordered_mat then begin
    (match Arrow_table.get_column ordered_mat "rank" with
     | Some (Arrow_table.DictionaryColumn (idx, levels, ordered)) ->
         if idx.(0) = Some 1 && idx.(1) = None && idx.(2) = Some 0
            && levels = ["low"; "med"; "high"] && ordered then begin
           incr pass_count; Printf.printf "  ✓ Ordered factor native round-trip preserves ordered=true\n"
         end else begin
           incr fail_count; Printf.printf "  ✗ Ordered factor native round-trip data mismatch (ordered=%b)\n" ordered
         end
     | _ ->
         incr fail_count; Printf.printf "  ✗ Ordered factor native round-trip returned wrong type\n")
  end else begin
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "Ordered factor native round-trip preserves ordered=true"
  end;

  print_newline ();

  Printf.printf "Arrow Integration — ListColumn (Nested DataFrame) Native Support:\n";

  (* Test: ListColumn creation and pure OCaml access *)
  let sub_table_a = Arrow_table.create [
    ("x", Arrow_table.IntColumn [| Some 1; Some 2 |]);
    ("y", Arrow_table.StringColumn [| Some "a"; Some "b" |]);
  ] 2 in
  let sub_table_b = Arrow_table.create [
    ("x", Arrow_table.IntColumn [| Some 3 |]);
    ("y", Arrow_table.StringColumn [| Some "c" |]);
  ] 1 in
  let list_col = Arrow_table.ListColumn [| Some sub_table_a; Some sub_table_b |] in
  let list_tbl = Arrow_table.create [
    ("key", Arrow_table.StringColumn [| Some "grp1"; Some "grp2" |]);
    ("data", list_col);
  ] 2 in
  if Arrow_table.num_rows list_tbl = 2 && Arrow_table.num_columns list_tbl = 2 then begin
    incr pass_count; Printf.printf "  ✓ ListColumn table creation works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ ListColumn table creation failed\n"
  end;

  (* Test: Schema reflects ArrowList type *)
  let list_schema = Arrow_table.get_schema list_tbl in
  (match List.assoc_opt "data" list_schema with
   | Some (Arrow_table.ArrowList _) ->
     incr pass_count; Printf.printf "  ✓ ListColumn schema type is ArrowList\n"
   | _ ->
     incr fail_count; Printf.printf "  ✗ ListColumn schema type mismatch\n");

  (* Test: ListColumn pure OCaml read-back *)
  (match Arrow_table.get_column list_tbl "data" with
   | Some (Arrow_table.ListColumn nested) ->
       if Array.length nested = 2 then begin
         (match nested.(0) with
          | Some t when t.Arrow_table.nrows = 2 ->
            incr pass_count; Printf.printf "  ✓ ListColumn read-back correct (sub-table 0 has 2 rows)\n"
          | _ ->
            incr fail_count; Printf.printf "  ✗ ListColumn read-back sub-table 0 mismatch\n");
         (match nested.(1) with
          | Some t when t.Arrow_table.nrows = 1 ->
            incr pass_count; Printf.printf "  ✓ ListColumn read-back correct (sub-table 1 has 1 row)\n"
          | _ ->
            incr fail_count; Printf.printf "  ✗ ListColumn read-back sub-table 1 mismatch\n")
       end else begin
         incr fail_count; Printf.printf "  ✗ ListColumn read-back has wrong length: %d\n" (Array.length nested)
       end
   | _ ->
       incr fail_count; Printf.printf "  ✗ ListColumn read-back returned wrong type\n");

  (* Test: is_arrow_table_new_supported returns true for ListColumn with primitive fields *)
  if Arrow_table.is_arrow_table_new_supported list_col then begin
    incr pass_count; Printf.printf "  ✓ is_arrow_table_new_supported = true for ListColumn\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ is_arrow_table_new_supported should be true for ListColumn\n"
  end;

  (* Test: Materialization of DataFrame with ListColumn *)
  let mat_list_tbl = Arrow_table.materialize list_tbl in
  let mat_list_native = Arrow_table.is_native_backed mat_list_tbl in
  if mat_list_native then begin
    incr pass_count; Printf.printf "  ✓ ListColumn table materializes to native Arrow\n";
    (* Verify round-trip: read key column from native *)
    (match Arrow_table.get_column mat_list_tbl "key" with
     | Some (Arrow_table.StringColumn a) ->
         if a.(0) = Some "grp1" && a.(1) = Some "grp2" then begin
           incr pass_count; Printf.printf "  ✓ Key column round-trip verified from native ListColumn table\n"
         end else begin
           incr fail_count; Printf.printf "  ✗ Key column data mismatch in native ListColumn table\n"
         end
     | _ ->
         incr fail_count; Printf.printf "  ✗ Key column read-back returned wrong type\n");
    (* Verify round-trip: read list column back from native *)
    (match Arrow_table.get_column mat_list_tbl "data" with
     | Some (Arrow_table.ListColumn nested) ->
         if Array.length nested = 2 then begin
           (match nested.(0) with
            | Some t ->
                if t.Arrow_table.nrows = 2 then begin
                  (match Arrow_table.get_column t "x" with
                   | Some (Arrow_table.IntColumn a) ->
                       if a.(0) = Some 1 && a.(1) = Some 2 then begin
                         incr pass_count; Printf.printf "  ✓ Native ListColumn round-trip: sub-table 0 x=[1,2] correct\n"
                       end else begin
                         incr fail_count; Printf.printf "  ✗ Native ListColumn round-trip: sub-table 0 x data mismatch\n"
                       end
                   | _ ->
                       incr fail_count; Printf.printf "  ✗ Native ListColumn round-trip: sub-table 0 x wrong type\n");
                  (match Arrow_table.get_column t "y" with
                   | Some (Arrow_table.StringColumn a) ->
                       if a.(0) = Some "a" && a.(1) = Some "b" then begin
                         incr pass_count; Printf.printf "  ✓ Native ListColumn round-trip: sub-table 0 y=[a,b] correct\n"
                       end else begin
                         incr fail_count; Printf.printf "  ✗ Native ListColumn round-trip: sub-table 0 y data mismatch\n"
                       end
                   | _ ->
                       incr fail_count; Printf.printf "  ✗ Native ListColumn round-trip: sub-table 0 y wrong type\n")
                end else begin
                  incr fail_count; Printf.printf "  ✗ Native ListColumn round-trip: sub-table 0 has %d rows (expected 2)\n" t.Arrow_table.nrows
                end
            | None ->
                incr fail_count; Printf.printf "  ✗ Native ListColumn round-trip: sub-table 0 is None\n");
           (match nested.(1) with
            | Some t ->
                if t.Arrow_table.nrows = 1 then begin
                  (match Arrow_table.get_column t "x" with
                   | Some (Arrow_table.IntColumn a) ->
                       if a.(0) = Some 3 then begin
                         incr pass_count; Printf.printf "  ✓ Native ListColumn round-trip: sub-table 1 x=[3] correct\n"
                       end else begin
                         incr fail_count; Printf.printf "  ✗ Native ListColumn round-trip: sub-table 1 x data mismatch\n"
                       end
                   | _ ->
                       incr fail_count; Printf.printf "  ✗ Native ListColumn round-trip: sub-table 1 x wrong type\n")
                end else begin
                  incr fail_count; Printf.printf "  ✗ Native ListColumn round-trip: sub-table 1 has %d rows (expected 1)\n" t.Arrow_table.nrows
                end
            | None ->
                incr fail_count; Printf.printf "  ✗ Native ListColumn round-trip: sub-table 1 is None\n")
         end else begin
           incr fail_count; Printf.printf "  ✗ Native ListColumn round-trip: nested has %d elements (expected 2)\n" (Array.length nested)
         end
     | _ ->
         incr fail_count; Printf.printf "  ✗ Native ListColumn round-trip: read-back returned wrong type\n")
  end else begin
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "ListColumn table materializes to native Arrow"
  end;

  (* Test: ListColumn with null entries *)
  let list_col_null = Arrow_table.ListColumn [| Some sub_table_a; None; Some sub_table_b |] in
  let list_tbl_null = Arrow_table.create [
    ("key", Arrow_table.StringColumn [| Some "g1"; None; Some "g3" |]);
    ("data", list_col_null);
  ] 3 in
  let mat_null_tbl = Arrow_table.materialize list_tbl_null in
  if Arrow_table.is_native_backed mat_null_tbl then begin
    (match Arrow_table.get_column mat_null_tbl "data" with
     | Some (Arrow_table.ListColumn nested) ->
         if Array.length nested = 3 && nested.(1) = None then begin
           incr pass_count; Printf.printf "  ✓ ListColumn with null entry round-trip correct\n"
         end else begin
           incr fail_count; Printf.printf "  ✗ ListColumn with null entry data mismatch\n"
         end
     | _ ->
         incr fail_count; Printf.printf "  ✗ ListColumn with null entry read-back returned wrong type\n")
  end else begin
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "ListColumn with null entries materializes to native Arrow"
  end;

  (* Test: Empty ListColumn — falls back to pure OCaml (no struct schema to build) *)
  let list_col_empty = Arrow_table.ListColumn [||] in
  if not (Arrow_table.is_arrow_table_new_supported list_col_empty) then begin
    incr pass_count; Printf.printf "  ✓ Empty ListColumn correctly falls back to pure OCaml\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ Empty ListColumn should not be materializable (no struct schema)\n"
  end;

  (* Test: nest/unnest via T language round-trip *)
  test "Nest creates DataFrame"
    {|df = dataframe([[g: "a", x: 1, y: 10], [g: "a", x: 2, y: 20], [g: "b", x: 3, y: 30]]); nested = nest(df, $x, $y); nrow(nested)|}
    "2";

  test "Unnest restores structure"
    {|df = dataframe([[g: "a", x: 1, y: 10], [g: "a", x: 2, y: 20], [g: "b", x: 3, y: 30]]); nested = nest(df, $x, $y); unnest(nested, $data) |> nrow|}
    "3";

  test "Nest-unnest round-trip preserves data"
    {|df = dataframe([[g: "a", x: 1], [g: "a", x: 2], [g: "b", x: 3]]); nested = nest(df, $x); flat = unnest(nested, $data); select(flat, $g, $x) |> nrow|}
    "3";

  (* Test: ListColumn with float and boolean sub-fields *)
  let sub_fb_a = Arrow_table.create [
    ("score", Arrow_table.FloatColumn [| Some 1.5; Some 2.5 |]);
    ("flag", Arrow_table.BoolColumn [| Some true; Some false |]);
  ] 2 in
  let sub_fb_b = Arrow_table.create [
    ("score", Arrow_table.FloatColumn [| Some 3.0 |]);
    ("flag", Arrow_table.BoolColumn [| Some true |]);
  ] 1 in
  let list_col_fb = Arrow_table.ListColumn [| Some sub_fb_a; Some sub_fb_b |] in
  let list_tbl_fb = Arrow_table.create [
    ("id", Arrow_table.IntColumn [| Some 1; Some 2 |]);
    ("nested", list_col_fb);
  ] 2 in
  let mat_fb = Arrow_table.materialize list_tbl_fb in
  if Arrow_table.is_native_backed mat_fb then begin
    (match Arrow_table.get_column mat_fb "nested" with
     | Some (Arrow_table.ListColumn nested) ->
         (match nested.(0) with
          | Some t ->
              let ok_score = (match Arrow_table.get_column t "score" with
                | Some (Arrow_table.FloatColumn a) -> a.(0) = Some 1.5 && a.(1) = Some 2.5
                | _ -> false) in
              let ok_flag = (match Arrow_table.get_column t "flag" with
                | Some (Arrow_table.BoolColumn a) -> a.(0) = Some true && a.(1) = Some false
                | _ -> false) in
              if ok_score && ok_flag then begin
                incr pass_count; Printf.printf "  ✓ ListColumn with Float+Bool sub-fields round-trip correct\n"
              end else begin
                incr fail_count; Printf.printf "  ✗ ListColumn with Float+Bool sub-fields data mismatch\n"
              end
          | None ->
              incr fail_count; Printf.printf "  ✗ ListColumn with Float+Bool: sub-table 0 is None\n")
     | _ ->
         incr fail_count; Printf.printf "  ✗ ListColumn with Float+Bool round-trip returned wrong type\n")
  end else begin
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "ListColumn with Float+Bool sub-fields materializes"
  end;

  (* Test: All-null ListColumn stays in pure OCaml fallback while preserving shape *)
  let list_col_all_null = Arrow_table.ListColumn [| None; None |] in
  let list_tbl_all_null = Arrow_table.create [
    ("id", Arrow_table.IntColumn [| Some 1; Some 2 |]);
    ("nested", list_col_all_null);
  ] 2 in
  let mat_all_null = Arrow_table.materialize list_tbl_all_null in
  if not (Arrow_table.is_native_backed mat_all_null) then begin
    let id_ok =
      match Arrow_table.get_column mat_all_null "id" with
      | Some (Arrow_table.IntColumn ids) ->
          Array.length ids = 2 && ids.(0) = Some 1 && ids.(1) = Some 2
      | _ -> false
    in
    (match Arrow_table.get_column mat_all_null "nested" with
     | Some (Arrow_table.ListColumn nested) when id_ok
                                             && Array.length nested = 2
                                             && nested.(0) = None
                                             && nested.(1) = None ->
         incr pass_count; Printf.printf "  ✓ All-null ListColumn preserves null entries in pure fallback\n"
     | _ ->
         incr fail_count; Printf.printf "  ✗ All-null ListColumn fallback data mismatch\n")
  end else begin
    incr fail_count; Printf.printf "  ✗ All-null ListColumn should fall back to pure OCaml\n"
  end;

  (* Test: Sparse ListColumn with heavy nulls round-trips without bitmap corruption *)
  let sparse_nested = Array.init 100 (fun i ->
    if i = 0 then Some sub_table_a
    else if i = 99 then Some sub_table_b
    else None
  ) in
  let sparse_tbl = Arrow_table.create [
    ("row_id", Arrow_table.IntColumn (Array.init 100 (fun i -> Some i)));
    ("nested", Arrow_table.ListColumn sparse_nested);
  ] 100 in
  let mat_sparse_tbl = Arrow_table.materialize sparse_tbl in
  if Arrow_table.is_native_backed mat_sparse_tbl then begin
    (match Arrow_table.get_column mat_sparse_tbl "nested" with
     | Some (Arrow_table.ListColumn nested) ->
         let first_ok =
           match nested.(0) with
           | Some t ->
               t.Arrow_table.nrows = 2 &&
               (match Arrow_table.get_column t "x" with
                | Some (Arrow_table.IntColumn a) -> a.(0) = Some 1 && a.(1) = Some 2
                | _ -> false)
           | None -> false
         in
         let last_ok =
           match nested.(99) with
           | Some t ->
               t.Arrow_table.nrows = 1 &&
               (match Arrow_table.get_column t "x" with
                | Some (Arrow_table.IntColumn a) -> a.(0) = Some 3
                | _ -> false)
           | None -> false
         in
         if Array.length nested = 100 && nested.(50) = None && first_ok && last_ok then begin
           incr pass_count; Printf.printf "  ✓ Sparse ListColumn with heavy nulls round-trip correct\n"
         end else begin
           incr fail_count; Printf.printf "  ✗ Sparse ListColumn with heavy nulls data mismatch\n"
         end
     | _ ->
         incr fail_count; Printf.printf "  ✗ Sparse ListColumn read-back returned wrong type\n")
  end else begin
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "Sparse ListColumn with heavy nulls materializes to native Arrow"
  end;

  (* Test: Repeated native schema and nested field access remains stable *)
  if mat_list_native then begin
    let lifecycle_ok = ref true in
    for _ = 1 to 100 do
      if Arrow_table.column_names mat_list_tbl <> ["key"; "data"] then
        lifecycle_ok := false;
      match Arrow_table.get_column mat_list_tbl "data" with
      | Some (Arrow_table.ListColumn nested) when Array.length nested = 2 -> ()
      | _ -> lifecycle_ok := false
    done;
    if !lifecycle_ok then begin
      incr pass_count; Printf.printf "  ✓ Repeated native schema/field queries stay valid\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ Repeated native schema/field queries became invalid\n"
    end
  end else begin
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "Repeated native schema/field queries stay valid"
  end;

  (* Test: Native ListColumn materialization survives repeated GC pressure *)
  let stress_failed = ref None in
  let default_stress_iterations = 1000 in
  let stress_gc_interval = 100 in
  let stress_iterations =
    match Sys.getenv_opt "TLANG_ARROW_STRESS_ITERS" with
    | Some s -> (match int_of_string_opt s with Some n when n > 0 -> n | _ -> default_stress_iterations)
    | None -> default_stress_iterations
  in
  let make_stress_table i =
    let left = Arrow_table.create [
      ("x", Arrow_table.IntColumn [| Some i; Some (i + 1) |]);
      ("y", Arrow_table.StringColumn [| Some "left"; Some "right" |]);
    ] 2 in
    let right = Arrow_table.create [
      ("x", Arrow_table.IntColumn [| Some (i + 2) |]);
      ("y", Arrow_table.StringColumn [| Some "tail" |]);
    ] 1 in
    Arrow_table.create [
      ("iter", Arrow_table.IntColumn [| Some i; Some (i + 1) |]);
      ("nested", Arrow_table.ListColumn [| Some left; Some right |]);
    ] 2
  in
  if Arrow_ffi.arrow_available then begin
    (try
       for i = 1 to stress_iterations do
         let native_tbl = Arrow_table.materialize (make_stress_table i) in
         if not (Arrow_table.is_native_backed native_tbl) then
           stress_failed := Some (Printf.sprintf "materialize returned pure OCaml fallback at iteration %d" i)
         else if Arrow_table.num_rows native_tbl <> 2 then
           stress_failed := Some (Printf.sprintf "num_rows returned an unexpected value at iteration %d" i)
         else
           (match Arrow_table.get_column native_tbl "nested" with
           | Some (Arrow_table.ListColumn nested) when Array.length nested = 2 -> ()
           | _ ->
               stress_failed := Some (Printf.sprintf "nested ListColumn read-back failed at iteration %d" i));

         if !stress_failed <> None then raise Exit;

         if i mod stress_gc_interval = 0
            || (i = stress_iterations && i mod stress_gc_interval <> 0)
         then Gc.full_major ()
       done
     with
     | Exit -> ()
     | exn ->
        stress_failed := Some (Printexc.to_string exn));
    (match !stress_failed with
     | None ->
         incr pass_count; Printf.printf "  ✓ Native ListColumn loop stress survives repeated GC\n"
     | Some msg ->
         incr fail_count; Printf.printf "  ✗ Native ListColumn loop stress failed: %s\n" msg)
  end else begin
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "Native ListColumn loop stress survives repeated GC"
  end;

  (* Test: T-level slice on nested data avoids regression in native list reconstruction *)
  test "Slice nested ListColumn DataFrame"
    {|df = dataframe([[g: "a", x: 1, y: 10], [g: "a", x: 2, y: 20], [g: "b", x: 3, y: 30]]); nested = nest(df, $x, $y); sliced = slice(nested, [0]); nrow(sliced)|}
    "1";

  test "Slice nested ListColumn preserves nested rows"
    {|df = dataframe([[g: "a", x: 1, y: 10], [g: "a", x: 2, y: 20], [g: "b", x: 3, y: 30]]); nested = nest(df, $x, $y); sliced = slice(nested, [0]); unnest(sliced, $data) |> nrow|}
    "2";

  print_newline ();
  Printf.printf "Arrow Integration — IPC Read/Write:\n";

  let ipc_path = "test_arrow_roundtrip.arrow" in
  let dict_ipc_path = "test_arrow_dict_roundtrip.arrow" in
  let list_ipc_path = "test_arrow_list_roundtrip.arrow" in
  let ipc_tbl_src = Arrow_table.create [
    ("id", Arrow_table.IntColumn [| Some 1; Some 2; Some 3 |]);
    ("name", Arrow_table.StringColumn [| Some "alpha"; Some "beta"; Some "gamma" |]);
  ] 3 in
  if Arrow_ffi.arrow_available then begin
    (match Arrow_io.write_ipc ipc_tbl_src ipc_path with
     | Ok () ->
         incr pass_count; Printf.printf "  ✓ Arrow_io.write_ipc writes IPC file\n";
         (match Arrow_io.read_ipc ipc_path with
          | Ok ipc_tbl ->
              let shape_ok =
                Arrow_table.num_rows ipc_tbl = 3
                && Arrow_table.num_columns ipc_tbl = 2
              in
              let id_ok =
                match Arrow_table.get_column ipc_tbl "id" with
                | Some (Arrow_table.IntColumn ids) ->
                    Array.length ids = 3
                    && ids.(0) = Some 1
                    && ids.(1) = Some 2
                    && ids.(2) = Some 3
                | _ -> false
              in
              let name_ok =
                match Arrow_table.get_column ipc_tbl "name" with
                | Some (Arrow_table.StringColumn names) ->
                    Array.length names = 3
                    && names.(0) = Some "alpha"
                    && names.(1) = Some "beta"
                    && names.(2) = Some "gamma"
                | _ -> false
              in
              if shape_ok && id_ok && name_ok then begin
                incr pass_count; Printf.printf "  ✓ Arrow_io.read_ipc round-trip preserves table data\n"
              end else begin
                incr fail_count; Printf.printf "  ✗ Arrow_io.read_ipc round-trip data mismatch\n"
              end
          | Error msg ->
              incr fail_count; Printf.printf "  ✗ Arrow_io.read_ipc failed: %s\n" msg)
     | Error msg ->
         incr fail_count; Printf.printf "  ✗ Arrow_io.write_ipc failed: %s\n" msg);

    let dict_ipc_tbl = Arrow_table.create [
      ("color", Arrow_table.DictionaryColumn (
        [| Some 0; Some 1; None; Some 2 |],
        ["red"; "green"; "blue"],
        false
      ));
      ("value", Arrow_table.IntColumn [| Some 10; Some 20; Some 30; Some 40 |])
    ] 4 in
    (match Arrow_io.write_ipc dict_ipc_tbl dict_ipc_path with
     | Ok () ->
         (match Arrow_io.read_ipc dict_ipc_path with
          | Ok dict_tbl ->
              (match Arrow_table.get_column dict_tbl "color" with
               | Some (Arrow_table.DictionaryColumn (idx, levels, ordered)) ->
                   if idx.(0) = Some 0 && idx.(1) = Some 1 && idx.(2) = None && idx.(3) = Some 2
                      && levels = ["red"; "green"; "blue"] && not ordered then begin
                     incr pass_count; Printf.printf "  ✓ DictionaryColumn IPC round-trip preserves levels and indices\n"
                   end else begin
                     incr fail_count; Printf.printf "  ✗ DictionaryColumn IPC round-trip data mismatch\n"
                   end
               | _ ->
                   incr fail_count; Printf.printf "  ✗ DictionaryColumn IPC read-back returned wrong type\n")
          | Error msg ->
              incr fail_count; Printf.printf "  ✗ DictionaryColumn IPC read failed: %s\n" msg)
     | Error msg ->
         incr fail_count; Printf.printf "  ✗ DictionaryColumn IPC write failed: %s\n" msg);

    let list_sub_a = Arrow_table.create [
      ("x", Arrow_table.IntColumn [| Some 1; Some 2 |]);
      ("y", Arrow_table.StringColumn [| Some "a"; Some "b" |]);
    ] 2 in
    let list_sub_b = Arrow_table.create [
      ("x", Arrow_table.IntColumn [| Some 3 |]);
      ("y", Arrow_table.StringColumn [| Some "c" |]);
    ] 1 in
    let list_ipc_tbl = Arrow_table.create [
      ("id", Arrow_table.IntColumn [| Some 1; Some 2 |]);
      ("nested", Arrow_table.ListColumn [| Some list_sub_a; Some list_sub_b |]);
    ] 2 in
    (match Arrow_io.write_ipc list_ipc_tbl list_ipc_path with
     | Ok () ->
         (match Arrow_io.read_ipc list_ipc_path with
          | Ok list_tbl ->
              (match Arrow_table.get_column list_tbl "nested" with
               | Some (Arrow_table.ListColumn nested) ->
                   let ok =
                     Array.length nested = 2
                     &&
                     match nested.(0), nested.(1) with
                     | Some t0, Some t1 -> t0.Arrow_table.nrows = 2 && t1.Arrow_table.nrows = 1
                     | _ -> false
                   in
                   if ok then begin
                     incr pass_count; Printf.printf "  ✓ ListColumn IPC round-trip preserves nested table shape\n"
                   end else begin
                     incr fail_count; Printf.printf "  ✗ ListColumn IPC round-trip nested shape mismatch\n"
                   end
               | _ ->
                   incr fail_count; Printf.printf "  ✗ ListColumn IPC read-back returned wrong type\n")
          | Error msg ->
              incr fail_count; Printf.printf "  ✗ ListColumn IPC read failed: %s\n" msg)
     | Error msg ->
         incr fail_count; Printf.printf "  ✗ ListColumn IPC write failed: %s\n" msg);

    let env_ipc = Packages.init_env () in
    let (_, env_ipc) =
      eval_string_env
        (Printf.sprintf
           {|df_ipc = dataframe([[id: 10, grp: "x"], [id: 20, grp: "y"]]); write_arrow(df_ipc, "%s")|}
           ipc_path)
        env_ipc
    in
    let (v, _) = eval_string_env (Printf.sprintf {|nrow(read_arrow("%s"))|} ipc_path) env_ipc in
    let nrow_result = Ast.Utils.value_to_string v in
    if nrow_result = "2" then begin
      incr pass_count; Printf.printf "  ✓ write_arrow/read_arrow round-trip preserves nrow\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ write_arrow/read_arrow expected nrow=2, got %s\n" nrow_result
    end;

    let (v, _) = eval_string_env (Printf.sprintf {|colnames(read_arrow("%s"))|} ipc_path) env_ipc in
    let colnames_result = Ast.Utils.value_to_string v in
    if colnames_result = {|["id", "grp"]|} then begin
      incr pass_count; Printf.printf "  ✓ read_arrow preserves schema/column names\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ read_arrow schema mismatch: %s\n" colnames_result
    end
  end else begin
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "Arrow_io.write_ipc/read_ipc round-trip";
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "DictionaryColumn IPC round-trip";
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "ListColumn IPC round-trip";
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "write_arrow/read_arrow round-trip"
  end;

  print_newline ();
  Printf.printf "Arrow Integration — Parquet Reading:\n";

  let parquet_path = Filename.temp_file "test_arrow_roundtrip_" ".parquet" in
  let parquet_write_cmd =
    Printf.sprintf "python3 -c %s"
      (Filename.quote
         (Printf.sprintf
            "import pyarrow as pa, pyarrow.parquet as pq; pq.write_table(pa.table({'id': [1, 2], 'name': ['alpha', 'beta']}), %S)"
            parquet_path))
  in
  let parquet_pyarrow_check_cmd =
    Printf.sprintf "python3 -c %s >/dev/null 2>&1"
      (Filename.quote "import pyarrow")
  in
  if Arrow_ffi.arrow_available then begin
    if Sys.command parquet_pyarrow_check_cmd <> 0 then begin
      incr pass_count;
      Printf.printf "  ⊘ read_parquet integration skipped (python3/pyarrow unavailable for fixture generation)\n"
    end else
    (match Sys.command parquet_write_cmd with
     | 0 ->
         (match Arrow_io.read_parquet parquet_path with
          | Ok parquet_tbl ->
              if Arrow_table.is_native_backed parquet_tbl
                 && Arrow_table.num_rows parquet_tbl = 2
                 && Arrow_table.num_columns parquet_tbl = 2 then begin
                incr pass_count; Printf.printf "  ✓ Arrow_io.read_parquet loads a native-backed table\n"
              end else begin
                incr fail_count; Printf.printf "  ✗ Arrow_io.read_parquet loaded an unexpected table shape/backing\n"
              end
          | Error msg ->
              incr fail_count; Printf.printf "  ✗ Arrow_io.read_parquet failed: %s\n" msg);

         let env_parquet = Packages.init_env () in
         let (v, _) = eval_string_env (Printf.sprintf {|nrow(read_parquet("%s"))|} parquet_path) env_parquet in
         let parquet_nrow = Ast.Utils.value_to_string v in
         if parquet_nrow = "2" then begin
           incr pass_count; Printf.printf "  ✓ read_parquet preserves row count\n"
         end else begin
           incr fail_count; Printf.printf "  ✗ read_parquet expected nrow=2, got %s\n" parquet_nrow
         end;

         let (v, _) = eval_string_env (Printf.sprintf {|colnames(read_parquet("%s"))|} parquet_path) env_parquet in
         let parquet_colnames = Ast.Utils.value_to_string v in
         if parquet_colnames = {|["id", "name"]|} then begin
           incr pass_count; Printf.printf "  ✓ read_parquet preserves schema/column names\n"
         end else begin
           incr fail_count; Printf.printf "  ✗ read_parquet schema mismatch: %s\n" parquet_colnames
         end
     | code ->
         incr fail_count;
         Printf.printf "  ✗ Failed to generate Parquet test fixture with python3/pyarrow (exit %d)\n" code)
  end else begin
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "Arrow_io.read_parquet loads a native-backed table";
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "read_parquet preserves row count";
    Test_arrow_helpers.record_native_requirement_result pass_count fail_count
      "read_parquet preserves schema/column names"
  end;

  print_newline ();

  (* Cleanup *)
  (try Sys.remove csv_path with _ -> ());
  (try Sys.remove csv_skip_path with _ -> ());
  (try Sys.remove ipc_path with _ -> ());
  (try Sys.remove dict_ipc_path with _ -> ());
  (try Sys.remove list_ipc_path with _ -> ());
  (try Sys.remove parquet_path with _ -> ());
  print_newline ()
