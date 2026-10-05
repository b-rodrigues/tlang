(* tests/test_dangling_reads.ml *)

(* Tests for dangling pipeline-node reads in t check:
   DotAccess, pipeline_node, and two-argument get against known pipelines. *)

let parse_program input =
  let lexbuf = Lexing.from_string input in
  Parser.program Lexer.token lexbuf

let pipes = [
  ("p", { Check_utils.pni_names = ["raw"; "clean"; "model"];
          Check_utils.pni_patterns = [] });
]

let pipes_branch = [
  ("q", { Check_utils.pni_names = ["mid"];
          Check_utils.pni_patterns = [] });
]

let pipes_dotted = [
  ("p2", { Check_utils.pni_names = ["a.b"];
           Check_utils.pni_patterns = [] });
]

let run_tests pass_count fail_count failures _eval_string _eval_string_env _test =
  Printf.printf "=== dangling node reads ===\n\n";
  flush stdout;
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
  let diags ?(p = pipes) ?(bind = "p = 1") code =
    Check_utils.dangling_node_read_diagnostics ~pipelines:p
      (parse_program (bind ^ "\n" ^ code)) "test.t"
  in
  let check_count ?(p = pipes) ?(bind = "p = 1") name code expect =
    check name (List.length (diags ~p ~bind code) = expect)
  in
  let check_msg name code expected =
    match diags code with
    | [d] -> check name (d.Diagnostics.diag_message = expected)
    | _ -> check name false
  in
  check_count "dot access on existing node stays silent"
    {|x = p.raw|} 0;
  check_msg "dot access typo warns naming pipeline"
    {|x = read_node(p.modle)|}
    "Node `modle` not found in pipeline `p`. Valid nodes: raw, clean, model.";
  check "dot typo suggests closest node" (
    match diags {|x = p.modle|} with
    | [d] ->
        (match d.Diagnostics.diag_suggested_fix with
         | Diagnostics.Suggest_identifier { suggestion; _ } -> suggestion = "model"
         | _ -> false)
    | _ -> false);
  check_count "pipeline_node on existing node stays silent"
    {|pipeline_node(p, "clean")|} 0;
  check_count "pipeline_node typo warns"
    {|pipeline_node(p, "clena")|} 1;
  check_count "pipeline_node bare-word selector resolves silently"
    {|pipeline_node(p, $raw)|} 0;
  check_count "pipeline_node bare-word typo warns"
    {|pipeline_node(p, $modle)|} 1;
  check_count "match binder shadowing stays silent"
    "match(1) { p => p.raw }" 0;
  check_count "import alias shadowing stays silent"
    "import core [p = sum]\nx = p.raw" 0;
  check_count "block-local rebind stays silent"
    "f = \\() { p = 1; p.raw }" 0;
  check_count "nested-only binding reads local, stays silent"
    ~bind:"" {|f = \(x) { p = 1; p.b }|} 0;
  check_count "nested-only reassignment reads local, stays silent"
    ~bind:"" {|f = \(x) { p := 2; p.b }|} 0;
  check_count "typedecl name shadowing stays silent"
    "type p = { x: Int }\nx = p.raw" 0;
  check_count "deeply nested read still warns once (single-visit walk)"
    (let depth = 25 in
     let open_ = String.concat "" (List.init depth (fun _ -> "{ ")) in
     let close_ = String.concat "" (List.init depth (fun _ -> " }")) in
     open_ ^ "p.b" ^ close_) 1;
  check_count "two-argument get typo warns"
    {|get(p, "modle")|} 1;
  check_count "three-argument get stays silent (returns default)"
    {|get(p, "modle", 0)|} 0;
  check_count "dynamic node name stays silent"
    {|pipeline_node(p, n)|} 0;
  check_count "unknown pipeline stays silent"
    {|x = q.raw|} 0;
  check_count "branch suffix with declared origin stays silent"
    ~p:pipes_branch ~bind:"q = 1" {|x = q.mid_branch_1|} 0;
  check_count "branch suffix with unknown origin warns"
    ~p:pipes_branch ~bind:"q = 1" {|x = q.other_branch_1|} 1;
  check_count "dotted prefix read stays silent"
    ~p:pipes_dotted ~bind:"p2 = 1" {|x = p2.a|} 0;
  check_count "read inside lambda warns (evaluator never reaches it)"
    {|f = \(x) read_node(p.modle)|} 1;
  check_count "shadowed pipeline variable stays silent"
    {|f = \(p) p.raw|} 0;
  check_count "reassigned pipeline stays silent"
    "p := 2\nx = p.raw" 0;
  check_count "doubly assigned pipeline stays silent"
    "p = 2\nx = p.raw" 0;
  check_count "shadowed get stays silent"
    "get = \\(a, b) a\nx = get(p, \"modle\")" 0;
  check "distant name carries no fix" (
    match diags {|pipeline_node(p, "zzz")|} with
    | [d] ->
        (match d.Diagnostics.diag_suggested_fix with
         | Diagnostics.NoFix -> true
         | _ -> false)
    | _ -> false);
  (* End-to-end wiring through run_check with real files: the evaluated
     pipeline feeds node names, the VError gate skips the walk, and a
     top-level typo reports once as the runtime error. *)
  let write_tmp body =
    let path = Filename.temp_file "dangling_e2e" ".t" in
    let ch = open_out path in
    Fun.protect ~finally:(fun () -> close_out_noerr ch)
      (fun () -> output_string ch body);
    path
  in
  let run_file_check body =
    let path = write_tmp body in
    Fun.protect ~finally:(fun () -> (try Sys.remove path with Sys_error _ -> ()))
      (fun () ->
        let hook = !Check_utils.extra_diagnostics_hook in
        Fun.protect ~finally:(fun () -> Check_utils.extra_diagnostics_hook := hook)
          (fun () ->
            Check_utils.extra_diagnostics_hook := (fun _ -> []);
            let env = Packages.init_env () in
            Check_utils.run_check Typecheck.Strict path env))
  in
  let entries body =
    Diagnostics.check_result_entries (run_file_check body)
  in
  let dangling_msg = "Node `b` not found in pipeline `p`. Valid nodes: a." in
  let dangling_only body =
    List.filter (fun d -> d.Diagnostics.diag_message = dangling_msg) (entries body)
  in
  check "lambda-hidden typo warns through run_check" (
    match dangling_only "p = pipeline { a = 1 }\nf = \\(x: Int -> Int) read_node(p.b)\n1\n" with
    | [d] -> d.Diagnostics.diag_severity = Diagnostics.Warning
    | _ -> false);
  check "top-level typo surfaces as runtime KeyError with no dangling dup" (
    let body = "p = pipeline { a = 1 }\nx = pipeline_node(p, \"b\")\n" in
    let es = entries body in
    List.exists (fun d ->
      d.Diagnostics.diag_severity = Diagnostics.Error
      && Diagnostics.diagnostic_error_class d = Diagnostics.Key_error
    ) es
    && dangling_only body = []);
  print_newline ()
