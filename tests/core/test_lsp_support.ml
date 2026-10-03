let run_tests pass_count fail_count _failures _eval_string _eval_string_env _test =
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

  (* Analyzer inference: to_dataframe() returns TDataFrame type *)
  let df_scope, _ = analyze {|df = to_dataframe([[a: 1, b: 2]])|} in
  test_message "to_dataframe() infers TDataFrame type"
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

  (* ── Arithmetic type inference ─────────────────────────── *)
  Printf.printf "Analyzer — type inference:\n";

  let int_scope, _ = analyze "x = 1 + 2" in
  test_message "Int + Int infers TInt"
    (match Symbol_table.lookup int_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TInt; _ } -> true
     | _ -> false);

  let float_scope, _ = analyze "x = 1 + 2.5" in
  test_message "Int + Float infers TFloat"
    (match Symbol_table.lookup float_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TFloat; _ } -> true
     | _ -> false);

  let div_scope, _ = analyze "x = 10 / 2" in
  test_message "Int / Int infers TFloat (division always float)"
    (match Symbol_table.lookup div_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TFloat; _ } -> true
     | _ -> false);

  let mod_scope, _ = analyze "x = 5 % 2" in
  test_message "Int mod Int infers TInt"
    (match Symbol_table.lookup mod_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TInt; _ } -> true
     | _ -> false);

  (* ── Comparison type inference ─────────────────────────── *)
  let cmp_scope, _ = analyze "x = 1 == 2" in
  test_message "Int == Int infers TBool"
    (match Symbol_table.lookup cmp_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TBool; _ } -> true
     | _ -> false);

  let and_scope, _ = analyze "x = true && false" in
  test_message "Bool && Bool infers TBool"
    (match Symbol_table.lookup and_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TBool; _ } -> true
     | _ -> false);

  (* ── Unary operator inference ──────────────────────────── *)
  let not_scope, _ = analyze "x = !true" in
  test_message "!Bool infers TBool"
    (match Symbol_table.lookup not_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TBool; _ } -> true
     | _ -> false);

  let neg_scope, _ = analyze "x = -5" in
  test_message "negate Int infers TInt"
    (match Symbol_table.lookup neg_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TInt; _ } -> true
     | _ -> false);

  (* ── IfElse type inference ─────────────────────────────── *)
  let if_scope, _ = analyze "x = if (true) 1 else 2" in
  test_message "if(Int, Int) infers TInt"
    (match Symbol_table.lookup if_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TInt; _ } -> true
     | _ -> false);

  let if_mixed_scope, _ = analyze "x = if (true) 1 else 2.5" in
  test_message "if(Int, Float) infers TFloat"
    (match Symbol_table.lookup if_mixed_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TFloat; _ } -> true
     | _ -> false);

  (* ── Match type inference ──────────────────────────────── *)
  Printf.printf "Analyzer — match inference:\n";

  let match_scope, _ = analyze "x = match([1,2]) { [head, ..tail] => head, [] => 0 }" in
  test_message "match(Int, Int) infers TInt"
    (match Symbol_table.lookup match_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TInt; _ } -> true
     | _ -> false);

  let match_bool_scope, _ = analyze "x = match([1,2]) { [head, ..tail] => head > 0, [] => false }" in
  test_message "match(Bool, Bool) infers TBool"
    (match Symbol_table.lookup match_bool_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TBool; _ } -> true
     | _ -> false);

  (* ── ListLit type inference ────────────────────────────── *)
  Printf.printf "Analyzer — ListLit inference:\n";

  let list_int_scope, _ = analyze "x = [1, 2, 3]" in
  test_message "ListLit[Int, Int, Int] infers TInt"
    (match Symbol_table.lookup list_int_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TInt; _ } -> true
     | _ -> false);

  let list_mixed_scope, _ = analyze "x = [1, 2.5]" in
  test_message "ListLit[Int, Float] infers TAny (mixed)"
    (match Symbol_table.lookup list_mixed_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TAny; _ } -> true
     | _ -> false);

  let list_str_scope, _ = analyze {|x = ["a", "b"]|} in
  test_message "ListLit[String, String] infers TString"
    (match Symbol_table.lookup list_str_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TString; _ } -> true
     | _ -> false);

  let list_empty_scope, _ = analyze "x = []" in
  test_message "ListLit[] (empty) infers TAny"
    (match Symbol_table.lookup list_empty_scope "x" with
     | Some { Symbol_table.typ = Some Semantic_type.TAny; _ } -> true
     | _ -> false);

  (* ── Lambda type inference ─────────────────────────────── *)
  Printf.printf "Analyzer — Lambda inference:\n";

  let lambda_scope, _ = analyze "x = \\(a, b) a + b" in
  test_message "lambda infers TFunction with 2 params"
    (match Symbol_table.lookup lambda_scope "x" with
     | Some { Symbol_table.typ = Some (Semantic_type.TFunction (args, _)); _ } ->
       List.length args = 2
     | _ -> false);

  let lambda_scope2, _ = analyze "x = \\(n) n > 0" in
  test_message "lambda with 1 param infers TFunction"
    (match Symbol_table.lookup lambda_scope2 "x" with
     | Some { Symbol_table.typ = Some (Semantic_type.TFunction (args, _)); _ } ->
       List.length args = 1
     | _ -> false);

  let lambda_ret_scope, _ = analyze "x = \\(n) n > 0" in
  test_message "lambda infers return type TBool from body"
    (match Symbol_table.lookup lambda_ret_scope "x" with
     | Some { Symbol_table.typ = Some (Semantic_type.TFunction (_, Semantic_type.TBool)); _ } -> true
     | _ -> false);

  let lambda_int_ret, _ = analyze "x = \\(a, b) a + b" in
  test_message "lambda with untyped params infers TUnknown from body"
    (match Symbol_table.lookup lambda_int_ret "x" with
     | Some { Symbol_table.typ = Some (Semantic_type.TFunction (_, Semantic_type.TUnknown)); _ } -> true
     | _ -> false);

  (* ── select narrows columns ────────────────────────────── *)
  Printf.printf "Analyzer — select narrowing:\n";

  let tmp_csv = Filename.temp_file "test_lsp" ".csv" in
  let oc = open_out tmp_csv in
  output_string oc "mpg,cyl,disp,hp\n1,4,100,80\n";
  close_out oc;

  let select_scope, _ = analyze (Printf.sprintf "df = read_csv(\"%s\")\ns = select(df, \"mpg\", \"cyl\")" tmp_csv) in
  test_message "select narrows DataFrame to 2 columns"
    (match Symbol_table.lookup select_scope "s" with
     | Some { Symbol_table.typ = Some (Semantic_type.TDataFrame cols); _ } ->
       List.length cols = 2 && List.exists (fun c -> c.Semantic_type.name = "mpg") cols
     | _ -> false);

  (* ── mutate infers column types ─────────────────────────── *)
  Printf.printf "Analyzer — mutate column types:\n";

  let mutate_scope, _ = analyze (Printf.sprintf "df = read_csv(\"%s\")\nm = mutate(df, $new_col = $mpg > 20)" tmp_csv) in
  (try Sys.remove tmp_csv with _ -> ());
  test_message "mutate infers new column as TBool"
    (match Symbol_table.lookup mutate_scope "m" with
     | Some { Symbol_table.typ = Some (Semantic_type.TDataFrame cols); _ } ->
       (match List.find_opt (fun c -> c.Semantic_type.name = "new_col") cols with
        | Some c -> c.Semantic_type.col_typ = Semantic_type.TBool
        | None -> false)
     | _ -> false);

  (* ── types_compatible ───────────────────────────────────── *)
  Printf.printf "Ast.types_compatible:\n";

  test_message "Int compatible with Int"
    (Ast.types_compatible Ast.TInt Ast.TInt);
  test_message "Int compatible with Float (relaxed)"
    (Ast.types_compatible Ast.TInt Ast.TFloat);
  test_message "Float not compatible with Int"
    (not (Ast.types_compatible Ast.TFloat Ast.TInt));
  test_message "String not compatible with Int"
    (not (Ast.types_compatible Ast.TString Ast.TInt));
  test_message "Any compatible with anything (right)"
    (Ast.types_compatible Ast.TString (Ast.TCustom "Any"));
  test_message "Anything compatible with Any (left)"
    (Ast.types_compatible (Ast.TCustom "Any") Ast.TInt);
  test_message "TArrow structural match"
    (Ast.types_compatible
       (Ast.TArrow ([Ast.TInt; Ast.TInt], Ast.TInt))
       (Ast.TArrow ([Ast.TInt; Ast.TInt], Ast.TInt)));
  test_message "TArrow mismatch on param"
    (not (Ast.types_compatible
       (Ast.TArrow ([Ast.TString; Ast.TInt], Ast.TInt))
       (Ast.TArrow ([Ast.TInt; Ast.TInt], Ast.TInt))));
  test_message "TArrow mismatch on return"
    (not (Ast.types_compatible
       (Ast.TArrow ([Ast.TInt], Ast.TInt))
       (Ast.TArrow ([Ast.TInt], Ast.TString))));
  test_message "TList unknown elements match anything"
    (Ast.types_compatible (Ast.TList None) (Ast.TList (Some Ast.TInt)));
  test_message "TList elements widen like scalars"
    (Ast.types_compatible
       (Ast.TList (Some Ast.TInt)) (Ast.TList (Some Ast.TFloat)));
  test_message "TList element mismatch"
    (not (Ast.types_compatible
       (Ast.TList (Some Ast.TInt)) (Ast.TList (Some Ast.TString))));
  test_message "TDict unknown sides match anything"
    (Ast.types_compatible
       (Ast.TDict (None, None)) (Ast.TDict (Some Ast.TString, Some Ast.TInt)));
  test_message "Function matches arity-0 arrow"
    (Ast.types_compatible (Ast.TCustom "Function") (Ast.TArrow ([], Ast.TInt)));
  test_message "arity-0 arrow matches Function"
    (Ast.types_compatible (Ast.TArrow ([], Ast.TInt)) (Ast.TCustom "Function"));
  test_message "Function matches arity-1 arrow"
    (Ast.types_compatible (Ast.TCustom "Function") (Ast.TArrow ([Ast.TInt], Ast.TInt)));
  test_message "arity-1 arrow matches Function"
    (Ast.types_compatible (Ast.TArrow ([Ast.TInt], Ast.TInt)) (Ast.TCustom "Function"));
  test_message "Function matches arity-3 arrow"
    (Ast.types_compatible (Ast.TCustom "Function")
       (Ast.TArrow ([Ast.TInt; Ast.TString; Ast.TBool], Ast.TFloat)));
  test_message "arity-3 arrow matches Function"
    (Ast.types_compatible (Ast.TArrow ([Ast.TInt; Ast.TString; Ast.TBool], Ast.TFloat))
       (Ast.TCustom "Function"));
  test_message "Function still rejects non-arrow"
    (not (Ast.types_compatible (Ast.TCustom "Function") Ast.TInt));
  test_message "non-arrow still rejects Function"
    (not (Ast.types_compatible Ast.TInt (Ast.TCustom "Function")));
  test_message "from_string keeps 3-member unions whole"
    (match Semantic_type.from_string "Bool | List[Bool] | Vector[Bool]" with
     | Semantic_type.TUnion [a; b; c] ->
         a = Semantic_type.TBool
         && b = Semantic_type.TList Semantic_type.TBool
         && c = Semantic_type.TVector Semantic_type.TBool
     | _ -> false);
  test_message "from_string still absorbs Any unions"
    (Semantic_type.from_string "Int | Any" = Semantic_type.TAny);

  (* ── Semantic_type.to_ast_typ ────────────────────────────── *)
  Printf.printf "Semantic_type.to_ast_typ:\n";

  test_message "TInt maps to Ast.TInt"
    (Semantic_type.to_ast_typ Semantic_type.TInt = Ast.TInt);
  test_message "TFloat maps to Ast.TFloat"
    (Semantic_type.to_ast_typ Semantic_type.TFloat = Ast.TFloat);
  test_message "TString maps to Ast.TString"
    (Semantic_type.to_ast_typ Semantic_type.TString = Ast.TString);
  test_message "TBool maps to Ast.TBool"
    (Semantic_type.to_ast_typ Semantic_type.TBool = Ast.TBool);
  test_message "TAny maps to Ast.TCustom \"Any\""
    (Semantic_type.to_ast_typ Semantic_type.TAny = Ast.TCustom "Any");
  test_message "TUnknown maps to Ast.TUnknown (unknown stays unknown)"
    (Semantic_type.to_ast_typ Semantic_type.TUnknown = Ast.TUnknown);
  test_message "TFunction maps to Ast.TArrow"
    (match Semantic_type.to_ast_typ (Semantic_type.TFunction ([("a", Semantic_type.TInt)], Semantic_type.TString)) with
     | Ast.TArrow ([Ast.TInt], Ast.TString) -> true
     | _ -> false);
  test_message "TList maps to Ast.TList"
    (match Semantic_type.to_ast_typ (Semantic_type.TList Semantic_type.TInt) with
     | Ast.TList (Some Ast.TInt) -> true
     | _ -> false);
  test_message "TVector maps to Ast.TList (vectors check as lists)"
    (match Semantic_type.to_ast_typ (Semantic_type.TVector Semantic_type.TBool) with
     | Ast.TList (Some Ast.TBool) -> true
     | _ -> false);
  test_message "TDict maps to Ast.TDict"
    (match Semantic_type.to_ast_typ (Semantic_type.TDict (Semantic_type.TString, Semantic_type.TInt)) with
     | Ast.TDict (Some Ast.TString, Some Ast.TInt) -> true
     | _ -> false);
  test_message "TCustom round-trips to Ast.TCustom"
    (Semantic_type.to_ast_typ (Semantic_type.TCustom "Model") = Ast.TCustom "Model");
  test_message "nominal types match only themselves"
    (Ast.types_compatible (Ast.TCustom "Model") (Ast.TCustom "Model"));
  test_message "nominal types reject other names"
    (not (Ast.types_compatible (Ast.TCustom "Model") (Ast.TCustom "Pipeline")));
  test_message "union accepts any member"
    (Ast.types_compatible Ast.TInt (Ast.TUnion [Ast.TInt; Ast.TString]));
  test_message "union rejects non-members"
    (not (Ast.types_compatible Ast.TBool (Ast.TUnion [Ast.TInt; Ast.TString])));
  test_message "union requires all members on the left"
    (not (Ast.types_compatible
       (Ast.TUnion [Ast.TInt; Ast.TBool]) (Ast.TUnion [Ast.TInt; Ast.TString])));

  (* ── Annotation check via Check_utils ──────────────────── *)
  Printf.printf "Annotation check (via hook):\n";
  let tmp_file = Filename.temp_file "t_type_test" ".t" in
  let oc = open_out tmp_file in
  output_string oc "a: Int = 42\nb: Int = \"oops\"\n";
  close_out oc;
  let env = Packages.init_env () in
  (* NOTE: annotation diagnostics live in Check_utils.annotation_diagnostics
     (shared with repl.ml's check), so this hook cannot drift from the
     shipped logic. *)
  Check_utils.extra_diagnostics_hook := (fun filename ->
    try
      let ch = open_in filename in
      let content = really_input_string ch (in_channel_length ch) in
      close_in ch;
      let lexbuf = Lexing.from_string content in
      lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
      let program = Parser.program Lexer.token lexbuf in
      let scope = Symbol_table.create_scope () in
      Symbol_table.register_keywords scope;
      let analysis = Analyzer.analyze program scope in
      Check_utils.annotation_diagnostics program analysis.Analyzer.stmt_types filename
    with _ -> []);
  let cr = Check_utils.run_check Typecheck.Strict tmp_file env in
  let diags = Diagnostics.check_result_entries cr in
  test_message "run_check with hook: emits annotation warning for mismatch"
    (List.exists (fun d ->
      d.Diagnostics.diag_error_class = Diagnostics.Type_error &&
      d.Diagnostics.diag_severity = Warning &&
      d.Diagnostics.diag_message |> fun s ->
        String.length s > 10 && String.sub s 0 10 = "Variable `") diags);
  (* Reset hook *)
  Check_utils.extra_diagnostics_hook := (fun _ -> []);
  let cr2 = Check_utils.run_check Typecheck.Strict tmp_file env in
  let diags2 = Diagnostics.check_result_entries cr2 in
  test_message "run_check without hook: no annotation warnings"
    (not (List.exists (fun d ->
      d.Diagnostics.diag_severity = Warning && d.Diagnostics.diag_message |> fun s ->
        String.length s > 10 && String.sub s 0 10 = "Variable `") diags2));
  Sys.remove tmp_file;

  (* Unknown inference stays silent under annotations: `if` with
     mismatched branches infers Unknown, which matches every
     annotation. The `k` control still warns, so silence is not
     a broken check. *)
  let tmp_file_u = Filename.temp_file "t_type_unknown" ".t" in
  let oc_u = open_out tmp_file_u in
  output_string oc_u "u: Int = if (true) 1 else \"s\"\nk: Int = \"oops\"\n";
  close_out oc_u;
  Check_utils.extra_diagnostics_hook := (fun filename ->
    try
      let ch = open_in filename in
      let content = really_input_string ch (in_channel_length ch) in
      close_in ch;
      let lexbuf = Lexing.from_string content in
      lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
      let program = Parser.program Lexer.token lexbuf in
      let scope = Symbol_table.create_scope () in
      Symbol_table.register_keywords scope;
      let analysis = Analyzer.analyze program scope in
      Check_utils.annotation_diagnostics program analysis.Analyzer.stmt_types filename
    with _ -> []);
  let cr_u = Check_utils.run_check Typecheck.Strict tmp_file_u env in
  let diags_u = Diagnostics.check_result_entries cr_u in
  let var_warns = List.filter (fun d ->
    d.Diagnostics.diag_severity = Warning && d.Diagnostics.diag_message |> fun s ->
      String.length s > 10 && String.sub s 0 10 = "Variable `") diags_u in
  test_message "unknown inference stays silent while known mismatch warns"
    (List.length var_warns = 1
     && (let s = (List.hd var_warns).Diagnostics.diag_message in
         try ignore (Str.search_forward (Str.regexp_string "`k`") s 0); true
         with Not_found -> false));
  Check_utils.extra_diagnostics_hook := (fun _ -> []);
  Sys.remove tmp_file_u;

  (* Reassignment against a standing annotation warns; a compatible
     reassignment, an Any-annotated one, and an unannotated one stay
     silent. The shared helper (same as the shipped check) is installed
     as the hook again. *)
  let tmp_file2 = Filename.temp_file "tlang_reassign_check" ".t" in
  let oc2 = open_out tmp_file2 in
  output_string oc2 "x: Int = 1\nx := \"hello\"\ny: Int = 2\ny := 3\nw: Any = 1\nw := \"s\"\nz = 1\nz := \"s\"\n";
  close_out oc2;
  Check_utils.extra_diagnostics_hook := (fun filename ->
    try
      let ch = open_in filename in
      let content = really_input_string ch (in_channel_length ch) in
      close_in ch;
      let lexbuf = Lexing.from_string content in
      lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
      let program = Parser.program Lexer.token lexbuf in
      let scope = Symbol_table.create_scope () in
      Symbol_table.register_keywords scope;
      let analysis = Analyzer.analyze program scope in
      Check_utils.annotation_diagnostics program analysis.Analyzer.stmt_types filename
    with _ -> []);
  let cr3 = Check_utils.run_check Typecheck.Strict tmp_file2 env in
  let diags3 = Diagnostics.check_result_entries cr3 in
  let reassign_msgs = List.filter_map (fun d ->
    if d.Diagnostics.diag_severity = Warning
       && (let s = d.Diagnostics.diag_message in
           String.length s > 10 && String.sub s 0 10 = "Variable `"
           && (try ignore (Str.search_forward (Str.regexp_string "reassignment infers to") s 0); true
               with Not_found -> false))
    then Some d.Diagnostics.diag_message
    else None) diags3 in
  test_message "reassignment against annotation warns exactly once (for x)"
    (List.length reassign_msgs = 1
     && (let s = List.hd reassign_msgs in
         try ignore (Str.search_forward (Str.regexp_string "`x`") s 0); true
         with Not_found -> false));
  Check_utils.extra_diagnostics_hook := (fun _ -> []);
  Sys.remove tmp_file2;

  (* Each reassignment is judged on its own right-hand side: a later
     compatible reassignment does not silence an earlier violation, and a
     bad binding line still warns even when a later reassignment fixes it.
     Both cases were silent under the old post-analysis-scope lookup. *)
  let tmp_file3 = Filename.temp_file "tlang_reassign_multi" ".t" in
  let oc3 = open_out tmp_file3 in
  output_string oc3 "a: Int = 1\na := \"x\"\na := 3\nb: Int = \"oops\"\nb := 2\n";
  close_out oc3;
  Check_utils.extra_diagnostics_hook := (fun filename ->
    try
      let ch = open_in filename in
      let content = really_input_string ch (in_channel_length ch) in
      close_in ch;
      let lexbuf = Lexing.from_string content in
      lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
      let program = Parser.program Lexer.token lexbuf in
      let scope = Symbol_table.create_scope () in
      Symbol_table.register_keywords scope;
      let analysis = Analyzer.analyze program scope in
      Check_utils.annotation_diagnostics program analysis.Analyzer.stmt_types filename
    with _ -> []);
  let cr4 = Check_utils.run_check Typecheck.Strict tmp_file3 env in
  let diags4 = Diagnostics.check_result_entries cr4 in
  let warn_lines : int option list =
    diags4
    |> List.filter (fun d ->
        d.Diagnostics.diag_severity = Warning
        && (let s = d.Diagnostics.diag_message in
            String.length s > 10 && String.sub s 0 10 = "Variable `"))
    |> List.map (fun d -> d.Diagnostics.diag_line) in
  test_message "two-reassignment chain warns on lines 2 and 4 only"
    (List.sort compare warn_lines = [Some 2; Some 4]);
  Check_utils.extra_diagnostics_hook := (fun _ -> []);
  Sys.remove tmp_file3;

  print_newline ()
