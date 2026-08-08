(* tests/test_fix.ml *)
(* Tests for src/fix.ml — mechanical application of suggested_fix *)

let run_tests pass_count fail_count failures _eval_string _eval_string_env _test =
  Printf.printf "\n=== t fix tests ===\n\n";

  let check name condition =
    if condition then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  ✗ %s\n" name in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in

  Printf.printf "\napply_rename_column:\n";
  let test_apply_rename () =
    let tmp = Filename.temp_file "test_fix" ".t" in
    let oc = open_out tmp in
    output_string oc "clean = raw\n  |> filter($id > 1)\n  |> mutate(valid = $id + 1)\n";
    close_out oc;
    Fix.apply_rename_column ~file:tmp ~old_name:"id" ~new_name:"record_id";
    let ch = open_in tmp in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    Sys.remove tmp;
    let has_new_ref = (try let _ = Str.search_forward (Str.regexp "\\$record_id") content 0 in true with Not_found -> false) in
    let has_unchanged_valid = (try let _ = Str.search_forward (Str.regexp_string "valid") content 0 in true with Not_found -> false) in
    check "rename_column replaces $id with $record_id" has_new_ref;
    check "rename_column does not corrupt 'valid'" has_unchanged_valid
  in
  test_apply_rename ();

  let test_apply_rename_preserves_rhs () =
    let tmp = Filename.temp_file "test_fix" ".t" in
    let oc = open_out tmp in
    output_string oc "renamed = source |> rename(mpg2 = $mpg) |> filter($mpg > 20)\n";
    close_out oc;
    Fix.apply_rename_column ~file:tmp ~old_name:"mpg" ~new_name:"mpg2";
    let ch = open_in tmp in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    Sys.remove tmp;
    let has_rename_def = (try let _ = Str.search_forward (Str.regexp "rename(mpg2 = \\$mpg)") content 0 in true with Not_found -> false) in
    let has_filter_fixed = (try let _ = Str.search_forward (Str.regexp "filter(\\$mpg2") content 0 in true with Not_found -> false) in
    check "rename_column preserves $col in rename() RHS (= $old)" has_rename_def;
    check "rename_column fixes stale $col in filter()" has_filter_fixed
  in
  test_apply_rename_preserves_rhs ();

  let test_rename_skips_non_rename_named_args () =
    let tmp = Filename.temp_file "test_fix" ".t" in
    let oc = open_out tmp in
    output_string oc "x = source |> rename(mpg2 = $mpg) |> mutate(flag = $mpg > 20)\n";
    close_out oc;
    Fix.apply_rename_column ~file:tmp ~old_name:"mpg" ~new_name:"mpg2";
    let ch = open_in tmp in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    Sys.remove tmp;
    let has_rename_def = (try let _ = Str.search_forward (Str.regexp "rename(mpg2 = \\$mpg)") content 0 in true with Not_found -> false) in
    let has_mutate_fixed = (try let _ = Str.search_forward (Str.regexp "mutate(flag = \\$mpg2") content 0 in true with Not_found -> false) in
    check "rename_column preserves $col in rename() RHS (= $old)" has_rename_def;
    check "rename_column fixes $col in mutate() named arg" has_mutate_fixed
  in
  test_rename_skips_non_rename_named_args ();

  let test_rename_mutate_lhs_and_rhs () =
    let tmp = Filename.temp_file "test_fix" ".t" in
    let oc = open_out tmp in
    output_string oc "x = source |> rename(mpg2 = $mpg) |> mutate($mpg = $mpg + 1)\n";
    close_out oc;
    Fix.apply_rename_column ~file:tmp ~old_name:"mpg" ~new_name:"mpg2";
    let ch = open_in tmp in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    Sys.remove tmp;
    let has_rename_def = (try let _ = Str.search_forward (Str.regexp "rename(mpg2 = \\$mpg)") content 0 in true with Not_found -> false) in
    let mutate_content =
      (try let _ = Str.search_forward (Str.regexp_string "mutate(") content 0 in
           String.sub content (Str.match_end ()) (String.length content - Str.match_end ())
       with Not_found -> "")
    in
    let mutate_both_fixed = (try let _ = Str.search_forward (Str.regexp_string "$mpg2 = $mpg2") mutate_content 0 in true
                             with Not_found -> false) in
    check "rename_column preserves $col in rename() RHS" has_rename_def;
    check "rename_column fixes $col in mutate() LHS and RHS" mutate_both_fixed
  in
  test_rename_mutate_lhs_and_rhs ();

  let test_rename_comparison_operators () =
    let test_one ~op partial_line =
      let tmp = Filename.temp_file "test_fix" ".t" in
      let oc = open_out tmp in
      output_string oc (Printf.sprintf "x = df |> rename(mpg2 = $mpg) |> %s\n" partial_line);
      close_out oc;
      Fix.apply_rename_column ~file:tmp ~old_name:"mpg" ~new_name:"mpg2";
      let ch = open_in tmp in
      let content = really_input_string ch (in_channel_length ch) in
      close_in ch;
      Sys.remove tmp;
      let is_word_char = function
        | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> true
        | _ -> false
      in
      let count_word_boundary needle =
        let need_len = String.length needle in
        let rec count_all pos n =
          try
            let pos = Str.search_forward (Str.regexp_string needle) content pos in
            if pos + need_len >= String.length content
               || not (is_word_char content.[pos + need_len])
            then count_all (pos + 1) (n + 1)
            else count_all (pos + need_len) n
          with Not_found -> n
        in count_all 0 0
      in
      let new_count = count_word_boundary "$mpg2" in
      let old_count = count_word_boundary "$mpg" in
      check (Printf.sprintf "rename replaces both $mpg with $mpg2 (%s operator)" op) (new_count = 2 && old_count = 1)
    in
    test_one ~op:"==" "filter($mpg == $mpg)";
    test_one ~op:"!=" "filter($mpg != $mpg)";
    test_one ~op:"<=" "filter($mpg <= $mpg)";
    test_one ~op:">=" "filter($mpg >= $mpg)"
  in
  test_rename_comparison_operators ();

  Printf.printf "\nsuggested_fix roundtrip:\n";
  let test_roundtrip () =
    let fixes : Diagnostics.suggested_fix list = [
      Diagnostics.make_rename_column_fix ~old_name:"a" ~new_name:"b" ~edit_distance:1 ~is_unique:true ?target_node:(Some "step2") ?file:(Some "test.t") ();
      Diagnostics.make_add_node_arg_fix ~node:"filter" ~arg:"na_rm=true" ?file:(Some "test.t") ();
      Diagnostics.make_rename_node_fix ~old_name:"count" ~new_name:"count_node" ?target_node:(Some "count") ?file:(Some "test.t") ();
      Diagnostics.make_suggest_identifier_fix ~name:"prnt" ~suggestion:"print" ~edit_distance:1 ~is_unique:true ?file:(Some "test.t") ();
      Diagnostics.make_run_command_fix ~command:"t init ." ~description:"Initialize tproject.toml" ?file:(Some "test.t") ();
      Diagnostics.no_fix;
    ] in
    let all_ok = List.for_all (fun fix ->
      let json = Diagnostics.suggested_fix_to_yojson fix in
      let roundtrip = Diagnostics.suggested_fix_of_yojson json in
      match fix, roundtrip with
      | NoFix, NoFix -> true
      | Rename_column { old_name = o1; new_name = n1; target_node = tn1; _ }, Rename_column { old_name = o2; new_name = n2; target_node = tn2; _ } ->
          o1 = o2 && n1 = n2 && tn1 = tn2
      | Rename_node { old_name = o1; new_name = n1; target_node = tn1; _ }, Rename_node { old_name = o2; new_name = n2; target_node = tn2; _ } ->
          o1 = o2 && n1 = n2 && tn1 = tn2
      | Add_node_arg { node = n1; arg = a1; target_node = tn1; _ }, Add_node_arg { node = n2; arg = a2; target_node = tn2; _ } ->
          n1 = n2 && a1 = a2 && tn1 = tn2
      | Suggest_identifier { name = nm1; suggestion = s1; _ }, Suggest_identifier { name = nm2; suggestion = s2; _ } ->
          nm1 = nm2 && s1 = s2
      | Run_command { command = cmd1; description = desc1; _ }, Run_command { command = cmd2; description = desc2; _ } ->
          cmd1 = cmd2 && desc1 = desc2
      | _ -> false
    ) fixes in
    check "suggested_fix roundtrips through JSON" all_ok
  in
  test_roundtrip ();

  Printf.printf "\napply_add_node_arg:\n";
  let test_apply_add_node_arg () =
    let tmp = Filename.temp_file "test_fix_add_arg" ".t" in
    let oc = open_out tmp in
    output_string oc "raw = node(\n  command = read_csv(\"data.csv\"),\n  runtime = T\n)\n";
    close_out oc;
    let r = Fix.apply_add_node_arg ~file:tmp ~node:"raw" ~arg:"serializer = ^csv" in
    check "add_node_arg returns true when node found" r;
    let ch = open_in tmp in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    let has_serializer = (try let _ = Str.search_forward (Str.regexp_string "serializer = ^csv") content 0 in true with Not_found -> false) in
    check "add_node_arg inserts serializer" has_serializer;
    let has_comma_before = (try let _ = Str.search_forward (Str.regexp "runtime = T,") content 0 in true with Not_found -> false) in
    check "add_node_arg adds comma to previous arg" has_comma_before;
    let indent_re = Str.regexp "\\( +\\)serializer" in
    let indent = (try ignore (Str.search_forward indent_re content 0); Str.matched_group 1 content with Not_found -> "") in
    check "add_node_arg matches sibling indentation" (indent = "  ");
    Sys.remove tmp
  in
  test_apply_add_node_arg ();

  Printf.printf "\napply_add_node_arg (pyn):\n";
  let test_apply_add_node_arg_pyn () =
    let tmp = Filename.temp_file "test_fix_add_arg_pyn" ".t" in
    let oc = open_out tmp in
    output_string oc "calc = pyn(\n  command = <{\ndf = raw.copy()\ndf\n  }>,\n  runtime = Python\n)\n";
    close_out oc;
    let r = Fix.apply_add_node_arg ~file:tmp ~node:"calc" ~arg:"deserializer = ^csv" in
    check "add_node_arg returns true for pyn" r;
    let ch = open_in tmp in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    let has_deser = (try let _ = Str.search_forward (Str.regexp_string "deserializer = ^csv") content 0 in true with Not_found -> false) in
    check "add_node_arg works for pyn with raw code block" has_deser;
    let has_raw_code = (try let _ = Str.search_forward (Str.regexp_string "df = raw.copy()") content 0 in true with Not_found -> false) in
    check "add_node_arg preserves raw code block" has_raw_code;
    let has_comma_before = (try let _ = Str.search_forward (Str.regexp "runtime = Python,") content 0 in true with Not_found -> false) in
    check "add_node_arg adds comma before deserializer (pyn)" has_comma_before;
    Sys.remove tmp
  in
  test_apply_add_node_arg_pyn ();

  Printf.printf "\napply_add_node_arg not found:\n";
  let test_apply_add_node_arg_not_found () =
    let tmp = Filename.temp_file "test_fix_add_arg_miss" ".t" in
    let oc = open_out tmp in
    output_string oc "other = node(\n  command = read_csv(\"data.csv\")\n)\n";
    close_out oc;
    let original_content =
      let ch = open_in tmp in
      let c = really_input_string ch (in_channel_length ch) in
      close_in ch; c
    in
    let r = Fix.apply_add_node_arg ~file:tmp ~node:"nonexistent" ~arg:"serializer = ^csv" in
    check "add_node_arg returns false when node not found" (r = false);
    let ch = open_in tmp in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    check "add_node_arg does not modify file when node not found" (content = original_content);
    Sys.remove tmp
  in
  test_apply_add_node_arg_not_found ();

  Printf.printf "\nrename_node confidence:\n";
  let conf = match Diagnostics.make_rename_node_fix ~old_name:"count" ~new_name:"count_node" () with
    | Diagnostics.Rename_node { confidence = c; _ } -> c
    | _ -> Diagnostics.Low
  in
  check "rename_node confidence is Medium (completeness depends on file contents)" (conf = Diagnostics.Medium);

  Printf.printf "\napply_rename_node:\n";
  let read_file path =
    let ch = open_in path in
    let c = really_input_string ch (in_channel_length ch) in
    close_in ch; c
  in
  let test_apply_rename_node () =
    let tmp = Filename.temp_file "test_fix_rename_node" ".t" in
    let oc = open_out tmp in
    output_string oc {|p = pipeline {
  count = node(runtime = T, command = <{ 1 }>)
}
|};
    close_out oc;
    let r = Fix.apply_rename_node ~file:tmp ~old_name:"count" ~new_name:"count_node" in
    check "rename_node returns true when constructor-form node found" r;
    let content = read_file tmp in
    Sys.remove tmp;
    let has_renamed = (try let _ = Str.search_forward (Str.regexp_string "count_node = node(runtime = T") content 0 in true with Not_found -> false) in
    let has_old_node_gone = try ignore (Str.search_forward (Str.regexp_string "\ncount = node(") content 0); false with Not_found -> true in
    check "rename_node renames the node definition line" has_renamed;
    check "rename_node does not leave old definition" has_old_node_gone
  in
  test_apply_rename_node ();

  Printf.printf "\napply_rename_node refuses on downstream reference:\n";
  let test_rename_node_refuses () =
    let tmp = Filename.temp_file "test_fix_rename_node_ref" ".t" in
    let oc = open_out tmp in
    output_string oc {|p = pipeline {
  count = node(runtime = T, command = <{ 1 }>),
  model = count + 1
}
|};
    close_out oc;
    let original = read_file tmp in
    let r = Fix.apply_rename_node ~file:tmp ~old_name:"count" ~new_name:"count_node" in
    check "rename_node refuses (returns false) when a sibling expression references it" (r = false);
    check "rename_node leaves file untouched on refusal" (read_file tmp = original);
    Sys.remove tmp
  in
  test_rename_node_refuses ();

  let test_rename_node_refuses_deps () =
    let tmp = Filename.temp_file "test_fix_rename_node_deps" ".t" in
    let oc = open_out tmp in
    output_string oc {|p = pipeline {
  count = node(runtime = T, command = <{ 1 }>),
  model = node(command = <{ count + 1 }>, deps = [count])
}
|};
    close_out oc;
    let original = read_file tmp in
    let r = Fix.apply_rename_node ~file:tmp ~old_name:"count" ~new_name:"count_node" in
    check "rename_node refuses when a deps entry references it" (r = false);
    check "rename_node leaves file untouched on deps refusal" (read_file tmp = original);
    Sys.remove tmp
  in
  test_rename_node_refuses_deps ();

  Printf.printf "\napply_rename_node tolerates the node's own raw code block:\n";
  let test_rename_node_own_raw () =
    let tmp = Filename.temp_file "test_fix_rename_node_ownraw" ".t" in
    let oc = open_out tmp in
    output_string oc {|p = pipeline {
  count = node(
    runtime = R,
    command = <{
      df |> count(cyl)
    }>
  )
}
|};
    close_out oc;
    let r = Fix.apply_rename_node ~file:tmp ~old_name:"count" ~new_name:"count_node" in
    check "rename_node succeeds when the name appears only in its own raw code block" r;
    let content = read_file tmp in
    Sys.remove tmp;
    let has_renamed = (try let _ = Str.search_forward (Str.regexp_string "count_node = node(") content 0 in true with Not_found -> false) in
    let has_own_code = (try let _ = Str.search_forward (Str.regexp_string "df |> count(cyl)") content 0 in true with Not_found -> false) in
    check "rename_node renames the multi-line node definition" has_renamed;
    check "rename_node preserves the node's own raw code" has_own_code
  in
  test_rename_node_own_raw ();

  Printf.printf "\napply_rename_node not found / non-constructor:\n";
  let test_apply_rename_node_skip () =
    let tmp = Filename.temp_file "test_fix_rename_node_miss" ".t" in
    let oc = open_out tmp in
    output_string oc "count = 3\n";
    close_out oc;
    let original_content =
      let ch = open_in tmp in
      let c = really_input_string ch (in_channel_length ch) in
      close_in ch; c
    in
    let r = Fix.apply_rename_node ~file:tmp ~old_name:"count" ~new_name:"count_node" in
    check "rename_node returns false when no constructor-form definition found" (r = false);
    let ch = open_in tmp in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    check "rename_node does not modify file when nothing to rename" (content = original_content);
    Sys.remove tmp
  in
  test_apply_rename_node_skip ();

  Printf.printf "\napply_fix dispatch:\n";
  let test_apply_fix_noop () =
    let r = Fix.apply_fix ~file:"/dev/null" Diagnostics.no_fix in
    check "apply_fix returns false for NoFix" (r = false)
  in
  test_apply_fix_noop ();

  let test_apply_fix_node_arg () =
    let tmp = Filename.temp_file "test_fix_dispatch_arg" ".t" in
    let oc = open_out tmp in
    output_string oc "raw = node(\n  command = read_csv(\"data.csv\"),\n  runtime = T\n)\n";
    close_out oc;
    let r = Fix.apply_fix ~file:tmp (Diagnostics.make_add_node_arg_fix ~node:"raw" ~arg:"serializer = ^csv" ?target_node:(Some "raw") ?file:(Some tmp) ()) in
    let ch = open_in tmp in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    Sys.remove tmp;
    check "apply_fix returns true for Add_node_arg" r;
    let has_serializer = (try let _ = Str.search_forward (Str.regexp_string "serializer = ^csv") content 0 in true with Not_found -> false) in
    check "apply_fix patches file for Add_node_arg" has_serializer;
    let has_comma = (try let _ = Str.search_forward (Str.regexp "runtime = T,") content 0 in true with Not_found -> false) in
    check "apply_fix produces valid comma separation" has_comma
  in
  test_apply_fix_node_arg ();

  let test_apply_fix_node_arg_not_found () =
    let tmp = Filename.temp_file "test_fix_dispatch_miss" ".t" in
    let oc = open_out tmp in
    output_string oc "other = node(\n  command = read_csv(\"data.csv\")\n)\n";
    close_out oc;
    let r = Fix.apply_fix ~file:tmp (Diagnostics.make_add_node_arg_fix ~node:"nonexistent" ~arg:"serializer = ^csv" ?file:(Some tmp) ()) in
    Sys.remove tmp;
    check "apply_fix returns false for non-existent node" (r = false)
  in
  test_apply_fix_node_arg_not_found ();

  let test_apply_fix_rename_node () =
    let tmp = Filename.temp_file "test_fix_dispatch_ren_node" ".t" in
    let oc = open_out tmp in
    output_string oc "count = node(runtime = T, command = <{ 1 }>)\n";
    close_out oc;
    let r = Fix.apply_fix ~file:tmp (Diagnostics.make_rename_node_fix ~old_name:"count" ~new_name:"count_node" ?target_node:(Some "count") ?file:(Some tmp) ()) in
    let ch = open_in tmp in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    Sys.remove tmp;
    check "apply_fix returns true for Rename_node" r;
    let has_renamed = (try let _ = Str.search_forward (Str.regexp_string "count_node = node(") content 0 in true with Not_found -> false) in
    check "apply_fix patches file for Rename_node" has_renamed
  in
  test_apply_fix_rename_node ();

  Printf.printf "\nsort_fixes_by_descending_line:\n";
  let test_sort_fixes () =
    let d1 = { Diagnostics.
      diag_id = "T0001"; diag_error_class = Diagnostics.Name_error; diag_severity = Error;
      diag_phase = Schema; diag_node_id = None; diag_node_lang = None;
      diag_file = Some "test.t"; diag_line = Some 3; diag_column = None;
      diag_end_line = None; diag_end_column = None;
      diag_message = "first"; diag_expected = None; diag_actual = None;
      diag_caused_by = [];
      diag_suggested_fix = Diagnostics.make_rename_column_fix ~old_name:"a" ~new_name:"b" ~edit_distance:1 ~is_unique:true ?file:(Some "test.t") ?line:(Some 3) ();
    } in
    let d2 = { d1 with diag_id = "T0002"; diag_line = Some 10;
      diag_message = "second";
      diag_suggested_fix = Diagnostics.make_rename_column_fix ~old_name:"c" ~new_name:"d" ~edit_distance:1 ~is_unique:true ?file:(Some "test.t") ?line:(Some 10) ();
    } in
    let d3 = { d1 with diag_id = "T0003"; diag_line = Some 5;
      diag_message = "third";
      diag_suggested_fix = Diagnostics.make_rename_column_fix ~old_name:"e" ~new_name:"f" ~edit_distance:1 ~is_unique:true ?file:(Some "test.t") ?line:(Some 5) ();
    } in
    let sorted = Fix.sort_fixes_by_descending_line [d1; d2; d3] in
    let lines = List.filter_map (fun d -> d.Diagnostics.diag_line) sorted in
    check "sort_descending: first element has highest line" (lines = [10; 5; 3])
  in
  test_sort_fixes ();

  Printf.printf "\nword-boundary rename:\n";
  let test_rename_word_boundary () =
    let tmp = Filename.temp_file "test_fix_wb" ".t" in
    let oc = open_out tmp in
    output_string oc "clean = raw\n  |> filter($id > 1)\n  |> mutate($identity = $id + 1)\n";
    close_out oc;
    Fix.apply_rename_column ~file:tmp ~old_name:"id" ~new_name:"record_id";
    let ch = open_in tmp in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    Sys.remove tmp;
    let has_record_id = (try let _ = Str.search_forward (Str.regexp_string "$record_id") content 0 in true with Not_found -> false) in
    let has_identity_unchanged = (try let _ = Str.search_forward (Str.regexp_string "$identity") content 0 in true with Not_found -> false) in
    let no_record_identity = not (try let _ = Str.search_forward (Str.regexp_string "$record_identity") content 0 in true with Not_found -> false) in
    check "rename replaces $id with $record_id" has_record_id;
    check "rename does not corrupt $identity" has_identity_unchanged;
    check "rename does not produce $record_identity" no_record_identity
  in
  test_rename_word_boundary ();

  Printf.printf "\ndry-run counting:\n";
  let test_dry_run_counting () =
    let d1 = { Diagnostics.
      diag_id = "T1001"; diag_error_class = Diagnostics.Name_error; diag_severity = Error;
      diag_phase = Schema; diag_node_id = None; diag_node_lang = None;
      diag_file = Some "test.t"; diag_line = Some 5; diag_column = None;
      diag_end_line = None; diag_end_column = None;
      diag_message = "Column 'x' not found, did you mean 'x_new'?";
      diag_expected = None; diag_actual = None; diag_caused_by = [];
      diag_suggested_fix = Diagnostics.make_rename_column_fix ~old_name:"x" ~new_name:"x_new" ~edit_distance:1 ~is_unique:true ?file:(Some "test.t") ?line:(Some 5) ();
    } in
    let d2 = { d1 with diag_id = "T1002"; diag_line = Some 8;
      diag_message = "Column 'y' not found, did you mean 'y_new'?";
      diag_suggested_fix = Diagnostics.make_rename_column_fix ~old_name:"y" ~new_name:"y_new" ~edit_distance:1 ~is_unique:true ?file:(Some "test.t") ?line:(Some 8) ();
    } in
    let d3 = { d1 with diag_id = "T1003"; diag_line = Some 12;
      diag_message = "Node `pyn` depends on `rn` but has no explicit deserializer";
      diag_suggested_fix = Diagnostics.make_add_node_arg_fix ~node:"pyn" ~arg:"deserializer = ^csv" ?file:(Some "test.t") ();
    } in
    let d4 = { d1 with diag_id = "T1004"; diag_line = Some 15;
      diag_message = "Node `count` is reserved: `count` is a builtin function.";
      diag_suggested_fix = Diagnostics.make_rename_node_fix ~old_name:"count" ~new_name:"count_node" ?target_node:(Some "count") ?file:(Some "test.t") ?line:(Some 15) ();
    } in
    let fixes = [d1; d2; d3; d4] in
    let result = Fix.apply_fixes ~dry_run:true ~default_file:"test.t" fixes in
    check "dry_run: applied = 0" (result.Fix.applied = 0);
    check "dry_run: would_apply = 4" (result.Fix.would_apply = 4);
    check "dry_run: skipped = 0" (result.Fix.skipped = 0)
  in
  test_dry_run_counting ();

  Printf.printf "\napply_fixes non-dry-run:\n";
  let test_apply_fixes_real () =
    let tmp_rename = Filename.temp_file "test_fix_af" ".t" in
    let oc = open_out tmp_rename in
    output_string oc "clean = raw\n  |> filter($mg > 1)\n  |> mutate($name = $mg)\n";
    close_out oc;
    let d1 = { Diagnostics.
      diag_id = "T1003"; diag_error_class = Diagnostics.Name_error; diag_severity = Error;
      diag_phase = Schema; diag_node_id = None; diag_node_lang = None;
      diag_file = Some tmp_rename; diag_line = Some 3; diag_column = None;
      diag_end_line = None; diag_end_column = None;
      diag_message = "did you mean 'mpg' instead of 'mg'?"; diag_expected = None; diag_actual = None;
      diag_caused_by = [];
      diag_suggested_fix = Diagnostics.make_rename_column_fix ~old_name:"mg" ~new_name:"mpg" ~edit_distance:1 ~is_unique:true ?file:(Some tmp_rename) ?line:(Some 3) ();
    } in
    let result = Fix.apply_fixes ~dry_run:false ~default_file:tmp_rename [d1] in
    check "non-dry-run: applied = 1" (result.Fix.applied = 1);
    check "non-dry-run: would_apply = 0" (result.Fix.would_apply = 0);
    let ch = open_in tmp_rename in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    Sys.remove tmp_rename;
    let has_rename = (try let _ = Str.search_forward (Str.regexp "mpg") content 0 in true with Not_found -> false) in
    check "non-dry-run: file patched with rename_column()" has_rename
  in
  test_apply_fixes_real ();
