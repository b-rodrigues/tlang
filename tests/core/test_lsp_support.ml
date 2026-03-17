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

  (* Analyzer inference: dataframe() returns TDataFrame type *)
  let df_scope, _ = analyze {|df = dataframe([[a: 1, b: 2]])|} in
  test_message "dataframe() infers TDataFrame type"
    (match Symbol_table.lookup df_scope "df" with
     | Some { Symbol_table.typ = Some (Semantic_type.TDataFrame _); _ } -> true
     | _ -> false);

  (* Analyzer inference: filter() propagates schema *)
  let filter_scope = Symbol_table.create_scope () in
  Symbol_table.add filter_scope {
    Symbol_table.name = "my_df";
    kind = Symbol_table.Variable;
    typ = Some (Semantic_type.TDataFrame [
      { Semantic_type.name = "x"; col_typ = Semantic_type.TUnknown };
    ]);
    doc = None;
  };
  let filter_lexbuf = Lexing.from_string "df2 = filter(my_df, x > 0)" in
  let filter_program = Parser.program Lexer.token filter_lexbuf in
  ignore (Analyzer.analyze filter_program filter_scope);
  test_message "filter() propagates DataFrame schema"
    (match Symbol_table.lookup filter_scope "df2" with
     | Some { Symbol_table.typ = Some (Semantic_type.TDataFrame cols); _ } ->
         List.exists (fun (c : Semantic_type.column) -> c.name = "x") cols
     | _ -> false);

  (* Analyzer inference: mutate() adds new columns *)
  let mutate_scope = Symbol_table.create_scope () in
  Symbol_table.add mutate_scope {
    Symbol_table.name = "base_df";
    kind = Symbol_table.Variable;
    typ = Some (Semantic_type.TDataFrame [
      { Semantic_type.name = "x"; col_typ = Semantic_type.TUnknown };
    ]);
    doc = None;
  };
  let mutate_lexbuf = Lexing.from_string "df2 = mutate(base_df, y: x + 1)" in
  let mutate_program = Parser.program Lexer.token mutate_lexbuf in
  ignore (Analyzer.analyze mutate_program mutate_scope);
  test_message "mutate() adds new columns to DataFrame schema"
    (match Symbol_table.lookup mutate_scope "df2" with
     | Some { Symbol_table.typ = Some (Semantic_type.TDataFrame cols); _ } ->
         List.exists (fun (c : Semantic_type.column) -> c.name = "y") cols &&
         List.exists (fun (c : Semantic_type.column) -> c.name = "x") cols
     | _ -> false);

  (* read_parquet() infers empty TDataFrame (no CSV sniffing) *)
  let parquet_scope, _ = analyze {|df = read_parquet("some_file.parquet")|} in
  test_message "read_parquet() infers TDataFrame (empty schema)"
    (match Symbol_table.lookup parquet_scope "df" with
     | Some { Symbol_table.typ = Some (Semantic_type.TDataFrame _); _ } -> true
     | _ -> false);

  (* read_csv() with non-existent file infers empty TDataFrame gracefully *)
  let csv_scope, _ = analyze {|df = read_csv("nonexistent_file_xyz.csv")|} in
  test_message "read_csv() with missing file infers TDataFrame gracefully"
    (match Symbol_table.lookup csv_scope "df" with
     | Some { Symbol_table.typ = Some (Semantic_type.TDataFrame []); _ } -> true
     | _ -> false);

  (* ColumnRef observed columns: column refs are tracked *)
  let col_scope, _ = analyze "x = $my_col" in
  test_message "ColumnRef adds column name to observed_columns"
    (List.mem "my_col" (Symbol_table.get_observed_columns col_scope));

  (* add_observed_column ignores empty names *)
  let empty_scope = Symbol_table.create_scope () in
  Symbol_table.add_observed_column empty_scope "";
  Symbol_table.add_observed_column empty_scope "  ";
  test_message "add_observed_column ignores empty and whitespace-only names"
    (Symbol_table.get_observed_columns empty_scope = []);

  print_newline ()
