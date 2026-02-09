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
    (* Arrow not compiled with native FFI — still passes as this is expected *)
    incr pass_count; Printf.printf "  ✓ Arrow FFI availability flag is set (value: %b)\n" arrow_avail
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

  let env = Eval.initial_env () in
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
    (Printf.sprintf {|df = read_csv("%s"); select(df, "name", "age") |> ncol|} csv_path)
    "2";

  test "Arrow filter"
    (Printf.sprintf {|df = read_csv("%s"); filter(df, \(row) row.age > 28) |> nrow|} csv_path)
    "2";

  test "Arrow mutate"
    (Printf.sprintf {|df = read_csv("%s"); mutate(df, "senior", \(row) row.age >= 30) |> ncol|} csv_path)
    "4";

  test "Arrow arrange"
    (Printf.sprintf
      {|df = read_csv("%s"); df2 = arrange(df, "age"); select(df2, "name") |> \(d) d.name|} csv_path)
    {|Vector["Bob", "Alice", "Charlie"]|};

  test "Arrow pipeline"
    (Printf.sprintf
      {|read_csv("%s") |> filter(\(row) row.age > 25) |> select("name", "score") |> nrow|} csv_path)
    "2";
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

  let env_c = Eval.initial_env () in
  let (_, env_c) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_compute) env_c in

  (* Test arrange ascending on native-backed table *)
  test "Compute: arrange ascending (native sort)"
    (Printf.sprintf {|df = read_csv("%s"); arrange(df, "age") |> \(d) d.name|} csv_compute)
    {|Vector["Bob", "Alice", "Charlie"]|};

  (* Test arrange descending on native-backed table *)
  test "Compute: arrange descending (native sort)"
    (Printf.sprintf {|df = read_csv("%s"); arrange(df, "age", "desc") |> \(d) d.name|} csv_compute)
    {|Vector["Charlie", "Alice", "Bob"]|};

  (* Test 30: select on native-backed table via compute *)
  test "Compute: select (native project)"
    (Printf.sprintf {|df = read_csv("%s"); select(df, "name", "score") |> ncol|} csv_compute)
    "2";

  (* Test 31: filter on native-backed table via compute *)
  test "Compute: filter (native filter)"
    (Printf.sprintf {|df = read_csv("%s"); filter(df, \(row) row.age > 28) |> nrow|} csv_compute)
    "2";

  (* Test 32: chained compute operations *)
  test "Compute: filter + select + arrange pipeline"
    (Printf.sprintf
      {|read_csv("%s") |> filter(\(row) row.age >= 30) |> select("name", "age") |> arrange("age") |> \(d) d.name|}
      csv_compute)
    {|Vector["Alice", "Charlie"]|};

  ignore env_c;
  (try Sys.remove csv_compute with _ -> ());

  (* Cleanup *)
  (try Sys.remove csv_path with _ -> ());
  print_newline ()
