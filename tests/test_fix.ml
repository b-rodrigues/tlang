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

  Printf.printf "apply_cast:\n";
  let test_apply_cast () =
    let tmp = Filename.temp_file "test_fix" ".t" in
    let oc = open_out tmp in
    output_string oc "clean = raw\n  |> read_csv(\"data.csv\")\n  |> expect(columns = [\"id\"])\n";
    close_out oc;
    Fix.apply_cast ~file:tmp ~line:3 ~column:"amount" ~cast_to:"double";
    let ch = open_in tmp in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    Sys.remove tmp;
    let lines = String.split_on_char '\n' content in
    let line3 = List.nth lines 2 in
    check "cast inserts mutate() before expect()" (String.length line3 > 0 && (try let _ = Str.search_forward (Str.regexp "mutate") line3 0 in true with Not_found -> false))
  in
  test_apply_cast ();

  Printf.printf "\napply_rename_column:\n";
  let test_apply_rename () =
    let tmp = Filename.temp_file "test_fix" ".t" in
    let oc = open_out tmp in
    output_string oc "clean = raw |> expect(columns = [\"old_name\"])\n";
    close_out oc;
    Fix.apply_rename_column ~file:tmp ~old_name:"old_name" ~new_name:"new_name";
    let ch = open_in tmp in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    Sys.remove tmp;
    let has_new = (try let _ = Str.search_forward (Str.regexp_string "new_name") content 0 in true with Not_found -> false) in
    check "rename_column replaces old with new" has_new
  in
  test_apply_rename ();

  Printf.printf "\nsuggested_fix roundtrip:\n";
  let test_roundtrip () =
    let fixes : Diagnostics.suggested_fix list = [
      Cast { column = "x"; cast_to = "double"; file = Some "test.t"; line = Some 5 };
      Rename_column { old_name = "a"; new_name = "b"; file = Some "test.t"; line = None };
      Add_node_arg { node = "filter"; arg = "na_rm=true"; file = Some "test.t"; line = None };
      Pin_package_version { pkg = "dplyr"; version = "1.0.0"; file = Some "tproject.toml" };
      NoFix;
    ] in
    let all_ok = List.for_all (fun fix ->
      let json = Diagnostics.suggested_fix_to_yojson fix in
      let roundtrip = Diagnostics.suggested_fix_of_yojson json in
      match fix, roundtrip with
      | NoFix, NoFix -> true
      | Cast { column = c1; cast_to = t1; _ }, Cast { column = c2; cast_to = t2; _ } ->
          c1 = c2 && t1 = t2
      | Rename_column { old_name = o1; new_name = n1; _ }, Rename_column { old_name = o2; new_name = n2; _ } ->
          o1 = o2 && n1 = n2
      | Add_node_arg { node = n1; arg = a1; _ }, Add_node_arg { node = n2; arg = a2; _ } ->
          n1 = n2 && a1 = a2
      | Pin_package_version { pkg = p1; version = v1; _ }, Pin_package_version { pkg = p2; version = v2; _ } ->
          p1 = p2 && v1 = v2
      | _ -> false
    ) fixes in
    check "suggested_fix roundtrips through JSON" all_ok
  in
  test_roundtrip ();

  Printf.printf "\napply_fix dispatch:\n";
  let test_apply_fix_noop () =
    let r = Fix.apply_fix ~file:"/dev/null" Diagnostics.NoFix in
    check "apply_fix returns false for NoFix" (r = false)
  in
  test_apply_fix_noop ();

  let test_apply_fix_node_arg () =
    let r = Fix.apply_fix ~file:"/dev/null" (Diagnostics.Add_node_arg { node = "x"; arg = "y"; file = None; line = None }) in
    check "apply_fix returns false for Add_node_arg (unimplemented)" (r = false)
  in
  test_apply_fix_node_arg ()
