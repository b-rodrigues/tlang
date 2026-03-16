let run_tests pass_count fail_count _eval_string _eval_string_env _test =
  let test_message name predicate =
    if predicate then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  ✗ %s\n" name
    end
  in
  let analyze source =
    let scope = Symbol_table.create_scope () in
    Symbol_table.register_keywords scope;
    let lexbuf = Lexing.from_string source in
    let program = Parser.program Lexer.token lexbuf in
    let analysis = Analyzer.analyze program scope in
    (scope, analysis)
  in

  Printf.printf "LSP support helpers:\n";

  let base_scope = Symbol_table.create_scope () in
  Symbol_table.add base_scope
    {
      Symbol_table.name = "base_only";
      kind = Symbol_table.Variable;
      typ = Some Semantic_type.TInt;
      doc = None;
    };
  let copied_scope = Symbol_table.copy_scope base_scope in
  Symbol_table.add copied_scope
    {
      Symbol_table.name = "copied_only";
      kind = Symbol_table.Variable;
      typ = Some Semantic_type.TString;
      doc = None;
    };
  test_message "copy_scope keeps base bindings available"
    (match Symbol_table.lookup copied_scope "base_only" with
     | Some _ -> true
     | None -> false);
  test_message "copy_scope does not mutate original scope"
    (match Symbol_table.lookup base_scope "copied_only" with
     | Some _ -> false
     | None -> true);

  let analyzed_scope, analysis = analyze "x = 1;\ny = x" in
  test_message "analyze indexes assignment definitions"
    (match Analyzer.Definition_map.find_opt "x" analysis.Analyzer.definitions with
     | Some loc -> loc.Ast.line = 1 && loc.Ast.column = 1
     | None -> false);
  test_message "analyze populates scope types for assignments"
    (match Symbol_table.lookup analyzed_scope "y" with
     | Some { Symbol_table.typ = Some Semantic_type.TInt; _ } -> true
     | _ -> false);

  let reassigned_scope, reassigned_analysis = analyze "x = 1;\nx := 2.5" in
  test_message "definition index keeps first declaration location"
    (match Analyzer.Definition_map.find_opt "x" reassigned_analysis.Analyzer.definitions with
     | Some loc -> loc.Ast.line = 1 && loc.Ast.column = 1
     | None -> false);
  test_message "reassignment updates inferred scope type"
    (match Symbol_table.lookup reassigned_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TFloat; _ } -> true
     | _ -> false);

  print_newline ()
