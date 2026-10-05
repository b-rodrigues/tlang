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
  check_count "pipeline_node bare-word selector stays silent"
    {|pipeline_node(p, $raw)|} 0;
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
  print_newline ()
