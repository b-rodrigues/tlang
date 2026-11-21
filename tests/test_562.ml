(* tests/test_562.ml *)
(* 0.56.2 patch tests: Replace_text, is_failed, node_status, overview filter, strings *)

let run_tests pass_count fail_count failures _eval_string _eval_string_env _test test_env test_equal =
  Printf.printf "0.56.2 patch:\n";
  let env = Packages.init_env () in

  let check name condition =
    if condition then begin
      incr pass_count;
      Printf.printf "  SUCCESS %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  FAILURE %s\n" name in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in

  test_equal env "is_failed false on int"
    {|is_failed(1)|}
    "false";
  test_equal env "is_failed true on error"
    {|is_failed(error("boom"))|}
    "true";
  test_equal env "is_failed propagates NA"
    {|is_na(is_failed(na()))|}
    "true";
  test_env env "node_status Built on computed"
    {|p = pipeline { a = 1 }; node_status(p.a)|}
    "\"Built\"";
  test_env env "node_status Errored on error"
    {|node_status(error("boom"))|}
    "\"Errored\"";

  test_equal env "starts_with true"
    {|starts_with("hello", "he")|}
    "true";
  test_equal env "ends_with true"
    {|ends_with("hello", "lo")|}
    "true";
  test_env env "str_to_title basic"
    {|str_to_title("hello world")|}
    "\"Hello World\"";
  test_env env "str_to_title keeps multi-byte UTF-8 whole"
    {|str_to_title("école über αβγ")|}
    "\"École Über Αβγ\"";

  test_equal env "pipeline_overview only failed empty ok"
    {|p = pipeline { a = 1 }; pipeline_overview(p, only = "failed") |> nrow|}
    "0";
  test_equal env "pipeline_overview only all keeps every row"
    {|p = pipeline { a = 1 }; pipeline_overview(p, only = "all") |> nrow|}
    "1";
  test_equal env "pipeline_overview only positional"
    {|p = pipeline { a = 1 }; pipeline_overview(p, "all") |> nrow|}
    "1";
  test_env env "pipeline_overview only invalid is a ValueError"
    {|p = pipeline { a = 1 }; pipeline_overview(p, only = "bad")|}
    "must be failed, built, unbuilt, or all";
  test_env env "pipeline_overview_markdown only invalid is a ValueError"
    {|p = pipeline { a = 1 }; pipeline_overview_markdown(p, only = "bad")|}
    "must be failed, built, unbuilt, or all";
  test_env env "pipeline_overview_markdown has table"
    {|p = pipeline { a = 1 }; pipeline_overview_markdown(p)|}
    "| name |";

  test_env env "generic Int Float message"
    {|const = \<T>(x: T, y: T -> T) x; const(1, 2.5)|}
    "Type variable `T` has inconsistent types: Int vs Float. Int is not widened to Float in generic T. Convert explicitly.";

  (* Fix engine Replace_text *)
  let write_temp content =
    let tmp = Filename.temp_file "test562" ".t" in
    let oc = open_out tmp in
    output_string oc content;
    close_out oc;
    tmp
  in
  let read_file path =
    let ch = open_in path in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    content
  in

  let tmp = write_temp "p = pipeline { a = node(serializer = ^arrow) }\n" in
  let ok = Fix.apply_replace_text ~file:tmp ~old_text:"^arrow" ~new_text:"^ipc" () in
  let content = read_file tmp in
  Sys.remove tmp;
  check "Replace_text ^arrow to ^ipc applies" ok;
  check "Replace_text content has ^ipc"
    (try ignore (Str.search_forward (Str.regexp_string "^ipc") content 0); true with Not_found -> false);

  let tmp2 = write_temp "x = 1\n" in
  let outcome = Fix.scan_replace_text ~file:tmp2 ~old_text:"^ipc" () in
  Sys.remove tmp2;
  check "scan_replace_text absent is false" (outcome = Some false);

  (* A prefix match in valid code must not be rewritten: p.mode -> p.model
     must leave p.model and p.model_extra alone. *)
  let tmp3 = write_temp "a = p.model\nb = p.mode\n" in
  let scoped = Fix.scan_replace_text ~file:tmp3 ~old_text:"p.mode" ~line:2 () in
  let applied = Fix.apply_replace_text ~file:tmp3 ~old_text:"p.mode" ~new_text:"p.model" ~line:2 () in
  let content3 = read_file tmp3 in
  Sys.remove tmp3;
  check "Replace_text finds the exact site" (scoped = Some true);
  check "Replace_text applies at the site" applied;
  check "Replace_text leaves p.model intact"
    (content3 = "a = p.model\nb = p.model\n");

  (* A bare union case must not be rewritten inside a call or an identifier,
     and `t fix` is line-scoped. *)
  let tmp4 = write_temp "a = Missing()\nb = Missing\nc = MissingValue\n" in
  let applied4 = Fix.apply_replace_text ~file:tmp4 ~old_text:"Missing" ~new_text:"Missing()" ~line:2 () in
  let content4 = read_file tmp4 in
  Sys.remove tmp4;
  check "Replace_text bare union case applies" applied4;
  check "Replace_text does not nest or corrupt lookalikes"
    (content4 = "a = Missing()\nb = Missing()\nc = MissingValue\n");

  (* A repeated quoted argument on the same line: the diagnostic column picks
     the diagnosed occurrence, so an unrelated string is left alone. *)
  let tmp6 =
    write_temp "p = pipeline { a = 1 }\nx = \"a\"; y = read_log(\"a\")\n"
  in
  let applied6 =
    Fix.apply_replace_text ~file:tmp6 ~old_text:"\"a\"" ~new_text:"p.a"
      ~line:2 ~column:14 ()
  in
  let content6 = read_file tmp6 in
  Sys.remove tmp6;
  check "Replace_text column picks the diagnosed occurrence" applied6;
  check "Replace_text leaves the other string alone"
    (content6 = "p = pipeline { a = 1 }\nx = \"a\"; y = read_log(p.a)\n");

  (* Comments are never edited. *)
  let tmp5 = write_temp "a = 1 -- Missing here\nb = Missing\n" in
  let applied5 = Fix.apply_replace_text ~file:tmp5 ~old_text:"Missing" ~new_text:"Missing()" () in
  let content5 = read_file tmp5 in
  Sys.remove tmp5;
  check "Replace_text applies outside comments" applied5;
  check "Replace_text leaves comments untouched"
    (content5 = "a = 1 -- Missing here\nb = Missing()\n");

  (* Diagnostics fix kind *)
  let fix = Diagnostics.make_replace_text_fix ~old_text:"a" ~new_text:"b" () in
  let js = Diagnostics.suggested_fix_to_yojson fix in
  let kind = Yojson.Safe.Util.(js |> member "kind" |> to_string) in
  check "Replace_text JSON kind" (kind = "replace_text");

  (* A bare union case is diagnosed at the case name itself, even when the
     same identifier reappears later on the line as a payload type. Menhir
     shifts the lookahead `|` before the action runs, so the lexbuf position
     alone points past the case. *)
  let tmp_union = write_temp "type Tree = Leaf | Branch(Leaf)\n" in
  let union_diags =
    Diagnostics.check_result_entries
      (Check_utils.run_check Typecheck.Strict tmp_union (Packages.init_env ()))
  in
  let union_applied =
    List.filter_map (fun d ->
      match d.Diagnostics.diag_suggested_fix with
      | Diagnostics.Replace_text r ->
          Some (Fix.apply_replace_text ~file:tmp_union ~old_text:r.old_text
                  ~new_text:r.new_text ?line:r.line ?column:r.column ())
      | _ -> None) union_diags
    |> function
    | applied :: _ -> applied
    | [] -> false
  in
  let union_content = read_file tmp_union in
  Sys.remove tmp_union;
  check "bare union case fix applies at the case name" union_applied;
  check "bare union case fix leaves the payload type alone"
    (union_content = "type Tree = Leaf() | Branch(Leaf)\n");

  (* The arrow fix replaces the spelling the file uses, not a fixed `^arrow`:
     any other casing used to produce a fix that could not be applied. *)
  let tmp_upper = write_temp "p = pipeline { a = node(command = <{ 1 }>, serializer = ^ARROW) }\n" in
  let upper_old =
    Diagnostics.check_result_entries
      (Check_utils.run_check Typecheck.Strict tmp_upper (Packages.init_env ()))
    |> List.find_map (fun d ->
      match d.Diagnostics.diag_suggested_fix with
      | Diagnostics.Replace_text r -> Some r.old_text
      | _ -> None)
  in
  Sys.remove tmp_upper;
  check "arrow fix uses the written spelling" (upper_old = Some "^ARROW");

  (* AST-only diagnostics: the dead inspect pattern and the string read_log. *)
  let parse_source src =
    let lexbuf = Lexing.from_string src in
    Parser.program Lexer.token lexbuf
  in
  let contains haystack needle =
    try ignore (Str.search_forward (Str.regexp_string needle) haystack 0); true
    with Not_found -> false
  in
  let dead =
    Check_utils.dead_inspect_diagnostics
      (parse_source "x = is_error(inspect_node(p.a))\n") "t.t"
  in
  check "dead inspect pattern warns"
    (match dead with
     | [d] -> d.Diagnostics.diag_severity = Diagnostics.Warning
              && contains d.Diagnostics.diag_message "always false"
     | _ -> false);
  let read_log_diags =
    Check_utils.read_log_string_diagnostics
      (parse_source "p = pipeline { a = 1 }\nread_log(\"a\")\n") "t.t"
  in
  check "read_log string argument suggests p.a"
    (match read_log_diags with
     | [d] ->
         contains d.Diagnostics.diag_message "read_log(p.a)"
         && (match d.Diagnostics.diag_suggested_fix with
             | Diagnostics.Replace_text r -> r.old_text = "\"a\"" && r.new_text = "p.a"
             | _ -> false)
     | _ -> false);

  (* A read_log call that never runs (inside a lambda) has no runtime error to
     merge into. The string-argument error and the argument-type warning name
     the same site, so only the authoritative error stays. *)
  let sigs = Check_utils.builtin_sigs_of_env (Packages.init_env ()) in
  let type_hook filename =
    let ch = open_in filename in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    let lexbuf = Lexing.from_string content in
    lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
    let program = Parser.program Lexer.token lexbuf in
    let scope = Symbol_table.create_scope () in
    Symbol_table.register_keywords scope;
    Symbol_table.populate_from_env scope (Packages.init_env ());
    (* Analyze populates the scope the inference below reads. *)
    let _analysis = Analyzer.analyze program scope in
    Check_utils.call_type_diagnostics ~sigs ~infer:(Analyzer.infer_type scope) program filename
  in
  let saved_hook = !Check_utils.extra_diagnostics_hook in
  let tmp_dup =
    write_temp
      "p = pipeline { model = node(command = <{ 1 }>) }\nf = \\(x: Int -> String) read_log(\"model\")\n"
  in
  let dup_diags =
    Fun.protect ~finally:(fun () -> Check_utils.extra_diagnostics_hook := saved_hook)
      (fun () ->
         Check_utils.extra_diagnostics_hook := type_hook;
         Diagnostics.check_result_entries
           (Check_utils.run_check Typecheck.Strict tmp_dup (Packages.init_env ())))
  in
  Sys.remove tmp_dup;
  let at_site =
    List.filter (fun d -> d.Diagnostics.diag_line = Some 2) dup_diags
  in
  check "unexecuted read_log gets one diagnostic"
    (match at_site with
     | [d] -> d.Diagnostics.diag_severity = Diagnostics.Error
     | _ -> false);

  (* Doctor: PMML detection and the JVM warning stay Nix-pure advice. *)
  let doctor_dir = Filename.temp_file "t_doctor" ".d" in
  Sys.remove doctor_dir;
  Unix.mkdir doctor_dir 0o755;
  let project_file = Filename.concat doctor_dir "tproject.toml" in
  let oc = open_out project_file in
  output_string oc "[dependencies]\nR = [\"jpmml\"]\n";
  close_out oc;
  check "project_uses_pmml detects a PMML declaration"
    (Package_doctor.project_uses_pmml doctor_dir);
  let saved_jvm = Sys.getenv_opt "T_JPMML_JAVA" in
  Unix.putenv "T_JPMML_JAVA" (Filename.concat doctor_dir "missing-java");
  let jvm = Package_doctor.check_jvm_pmml () in
  (match saved_jvm with
   | Some v -> Unix.putenv "T_JPMML_JAVA" v
   (* No [Unix.unsetenv] here: an empty value reads as unset, which is
      exactly what the doctor checks test for. *)
   | None -> Unix.putenv "T_JPMML_JAVA" "");
  Sys.remove project_file;
  (try Unix.rmdir doctor_dir with Unix.Unix_error _ -> ());
  check "check_jvm_pmml warns on a missing T_JPMML_JAVA target"
    (List.exists (fun (i : Package_doctor.issue) ->
       contains i.Package_doctor.message "points to missing file") jvm);
  check "check_jvm_pmml stays Nix-pure"
    (List.for_all (fun (i : Package_doctor.issue) ->
       match i.Package_doctor.suggestion with
       | None -> true
       | Some s -> contains s "tproject.toml" && contains s "t update") jvm)
