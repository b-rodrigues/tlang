open Ast

let run_tests pass_count fail_count _eval_string _eval_string_env _test =
  let record name ok =
    if ok then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  ✗ %s\n" name
    end
  in
  let test_case name f =
    try record name (f ())
    with exn ->
      incr fail_count;
      Printf.printf "  ✗ %s\n    %s\n" name (Printexc.to_string exn)
  in
  let rec remove_path path =
    if Sys.file_exists path then
      if Sys.is_directory path then begin
        Sys.readdir path
        |> Array.iter (fun name -> remove_path (Filename.concat path name));
        Unix.rmdir path
      end else
        Sys.remove path
  in
  let create_temp_dir prefix =
    let base = Filename.get_temp_dir_name () in
    let rec loop attempt =
      if attempt >= 16 then
        failwith (Printf.sprintf "Failed to create temporary directory for %s" prefix)
      else
        let suffix =
          Int64.to_string
            (Int64.add
               (Int64.of_float (Unix.gettimeofday () *. 1_000_000.0))
               (Int64.of_int attempt))
        in
        let path =
          Filename.concat base
            (Printf.sprintf "tlang-%s-%d-%s" prefix (Unix.getpid ()) suffix)
        in
        try
          Unix.mkdir path 0o755;
          path
        with
        | Unix.Unix_error (Unix.EEXIST, _, _) -> loop (attempt + 1)
    in
    loop 0
  in
  let with_temp_dir prefix f =
    let base_dir = create_temp_dir prefix in
    Fun.protect
      ~finally:(fun () -> remove_path base_dir)
      (fun () -> f base_dir)
  in
  let with_cwd dir f =
    let old = Sys.getcwd () in
    Fun.protect
      ~finally:(fun () -> Sys.chdir old)
      (fun () ->
        Sys.chdir dir;
        f ())
  in
  let write_text path content =
    let oc = open_out path in
    output_string oc content;
    close_out oc
  in
  let read_text path =
    try
      let ic = open_in path in
      Fun.protect
        ~finally:(fun () -> close_in ic)
        (fun () -> really_input_string ic (in_channel_length ic))
    with exn ->
      failwith (Printf.sprintf "failed to read %s: %s" path (Printexc.to_string exn))
  in
  let locless node = { node; loc = None } in
  let mk_scope () = Symbol_table.create_scope () in
  let contains s sub =
    let s_len = String.length s in
    let sub_len = String.length sub in
    let rec loop i =
      if sub_len = 0 then true
      else if i + sub_len > s_len then false
      else if String.sub s i sub_len = sub then true
      else loop (i + 1)
    in
    loop 0
  in
  let sample_df_type =
    Semantic_type.TDataFrame [
      { Semantic_type.name = "value"; col_typ = Semantic_type.TUnknown };
      { Semantic_type.name = "measure"; col_typ = Semantic_type.TUnknown };
      { Semantic_type.name = "group"; col_typ = Semantic_type.TUnknown };
    ]
  in
  let sample_entry =
    let open Tdoc_types in
    {
      name = "plot/chart";
      description_brief = "Short description";
      description_full = "Longer explanation";
      params = [
        { name = "data"; type_info = Some "DataFrame"; description = "Input data" };
        { name = "keep"; type_info = Some "Bool"; description = "Keep rows" };
      ];
      return_value = Some { type_info = Some "Float"; description = "A result" };
      examples = [ "plot(chart: data, keep: true)" ];
      see_also = [ "other/fn" ];
      family = Some "graphics";
      is_export = true;
      intent = Some { purpose = "plot"; use_when = "visualising"; alternatives = Some "print" };
      package = Some "tdoc";
      source_path = "src/packages/core/plot.ml";
      line_number = 12;
    }
  in
  let expect_error_code code = function
    | VError info -> info.code = code
    | _ -> false
  in

  Printf.printf "Coverage — TDoc:\n";
  test_case "tdoc json wrappers and error path" (fun () ->
    let json =
      Tdoc_json.from_string {|{"name":"doc","count":2,"flag":true,"items":[1,2]}|}
    in
    let name_ok =
      match Tdoc_json.member "name" json with
      | Some v -> Tdoc_json.to_string v = Some "doc"
      | None -> false
    in
    let count_ok =
      match Tdoc_json.member "count" json with
      | Some v -> Tdoc_json.to_int v = Some 2
      | None -> false
    in
    let flag_ok =
      match Tdoc_json.member "flag" json with
      | Some v -> Tdoc_json.to_bool v = Some true && Tdoc_json.pattern_match_bool v
      | None -> false
    in
    let items_ok =
      match Tdoc_json.member "items" json with
      | Some v ->
          (match Tdoc_json.to_list v with
           | Some [_; _] -> List.length (Tdoc_json.pattern_match_array v) = 2
           | _ -> false)
      | None -> false
    in
    let invalid_ok =
      try
        ignore (Tdoc_json.from_string "{");
        false
      with
      | Tdoc_json.Json_error _ -> true
      | _ -> false
    in
    name_ok && count_ok && flag_ok && items_ok && invalid_ok
  );
  test_case "tdoc types roundtrip and markdown generation" (fun () ->
    let json = Tdoc_types.doc_entry_to_json sample_entry in
    let parsed = Tdoc_types.doc_entry_of_json (Tdoc_json.from_string json) in
    let doc = Tdoc_markdown.generate_function_doc parsed in
    let index =
      Tdoc_markdown.generate_index
        [ parsed; { parsed with name = "hidden"; is_export = false } ]
    in
    parsed.name = sample_entry.name
    && parsed.package = Some "tdoc"
    && String.contains doc '#'
    && String.contains doc '%'
    && String.contains doc '='
    && String.contains index '|'
    && not (contains index "hidden")
  );
  test_case "tdoc parser parses tags and infers names" (fun () ->
    let block =
      Tdoc_parser.parse_block
        [
          "Brief line";
          "More details";
          "@param keep :: Bool Keep rows";
          "@param data :: DataFrame Input data";
          "@return :: Float Result value";
          "@example";
          "plot(chart: data, keep: true)";
          "@seealso alpha, beta";
          "@family graphics";
          "@private";
        ]
        "sample.t"
        10
    in
    let parse_block_ok =
      let param_names = List.map (fun (p : Tdoc_types.param_doc) -> p.name) block.params in
      block.description_brief = "Brief line"
      && block.description_full = "More details"
      && block.is_export = false
      && block.family = Some "graphics"
      && param_names = [ "data"; "keep" ]
      && block.examples = [ "plot(chart: data, keep: true)" ]
      (* parse_block prepends then reverses per-tag entries, so @seealso items
         currently come back in reverse textual order. *)
      && block.see_also = [ "beta"; "alpha" ]
    in
    let parse_file_ok =
      with_temp_dir "tdoc" (fun dir ->
        let file = Filename.concat dir "doc_source.t" in
        write_text file
          {|--# Read data
--# @param data :: DataFrame Input
fn read_data(x) = x

--# Exported helper
--# @name explicit_name
export let helper = 1
|};
        match Tdoc_parser.parse_file file with
        | [ first; second ] ->
            first.name = "read_data"
            && second.name = "explicit_name"
            && first.line_number = 1
        | _ -> false)
    in
    parse_block_ok && parse_file_ok
  );
  print_newline ();

  Printf.printf "Coverage — Types, symbols, completion, analyzer:\n";
  test_case "semantic_type conversions render expected strings" (fun () ->
    let grouped =
      Semantic_type.TGroupedDataFrame
        ([ { Semantic_type.name = "value"; col_typ = Semantic_type.TFloat } ], [ "group" ])
    in
    let fn_ty =
      Semantic_type.TFunction ([ ("data", Semantic_type.TDataFrame []) ], Semantic_type.TBool)
    in
    Semantic_type.from_string "numeric" = Semantic_type.TFloat
    && Semantic_type.from_string "vector[int]" = Semantic_type.TAny
    && Semantic_type.from_string "list[string]" = Semantic_type.TAny
    && Semantic_type.from_string "mystery" = Semantic_type.TUnknown
    && Semantic_type.to_string grouped = "grouped_dataframe[value | groups: group]"
    && String.starts_with ~prefix:"Function(" (Semantic_type.to_string fn_ty)
  );
  test_case "symbol_table tracks dataframes, keywords, copies and env values" (fun () ->
    let scope = mk_scope () in
    Symbol_table.register_keywords scope;
    Symbol_table.add scope
      { Symbol_table.name = "df"; kind = Symbol_table.Variable; typ = Some sample_df_type; doc = Some "data" };
    Symbol_table.add_observed_column scope " observed_col ";
    let copied = Symbol_table.copy_scope scope in
    let env =
      Ast.Env.empty
      |> Ast.Env.add "count" (VInt 1)
      |> Ast.Env.add "helper"
           (VBuiltin {
             b_name = Some "helper";
             b_arity = 1;
             b_variadic = false;
             b_func = (fun _ _ -> VInt 0);
           })
    in
    Symbol_table.populate_from_env copied env;
    let names = Symbol_table.filter_symbols copied "he" |> List.map (fun s -> s.Symbol_table.name) in
    List.mem "if" (List.map (fun s -> s.Symbol_table.name) (Symbol_table.all scope))
    && Symbol_table.lookup scope "df" <> None
    && Symbol_table.get_observed_columns scope = [ "observed_col" ]
    && List.exists (fun s -> s.Symbol_table.name = "df") (Symbol_table.get_dataframes scope)
    && List.mem "helper" names
    && match Symbol_table.value_to_semantic_type (VLambda {
         params = [ "x" ];
         autoquote_params = [ false ];
         param_types = [ None ];
         return_type = None;
         generic_params = [];
         variadic = false;
         body = locless (Value (VInt 1));
         env = None;
       }) with
       | Some (Semantic_type.TFunction ([ ("x", Semantic_type.TUnknown) ], Semantic_type.TUnknown)) -> true
       | _ -> false
  );
  test_case "completion handles prefixes, members, arguments and columns" (fun () ->
    let scope = mk_scope () in
    Symbol_table.add scope
      { Symbol_table.name = "df"; kind = Symbol_table.Variable; typ = Some sample_df_type; doc = None };
    Symbol_table.add scope
      {
        Symbol_table.name = "summarise";
        kind = Symbol_table.Function;
        typ = Some (Semantic_type.TFunction ([ ("na_rm", Semantic_type.TBool); ("digits", Semantic_type.TInt) ], Semantic_type.TAny));
        doc = None;
      };
    Symbol_table.add_observed_column scope "model";
    let prefix_ok = Completion.extract_prefix "alpha" 5 = "alpha" in
    let comment_ok = Completion.extract_prefix "-- comment" 10 = "" in
    let string_ok = Completion.is_inside_comment_or_string "\"abc\"" 4 in
    let member_ok =
      let start, matches = Completion.complete scope ~buffer:"df.m" ~cursor:4 in
      start = 3 && matches = [ "measure"; "model" ]
    in
    let arg_ok =
      let start, matches = Completion.complete scope ~buffer:"summarise(na" ~cursor:12 in
      start = 10 && matches = [ "na_rm = " ]
    in
    let column_ok =
      let start, matches = Completion.complete scope ~buffer:"$m" ~cursor:2 in
      start = 1 && matches = [ "measure"; "model" ]
    in
    let fn_ok = Completion.find_surrounding_function "sum(x" 5 = Some ("sum", 3) in
    prefix_ok && comment_ok && string_ok && member_ok && arg_ok && column_ok && fn_ok
  );
  test_case "analyzer infers csv, mutate and definitions" (fun () ->
    with_temp_dir "analyzer" (fun dir ->
      let csv_path = Filename.concat dir "data.csv" in
      write_text csv_path "\"a\";b\n1;2\n";
      let scope = mk_scope () in
      let csv_expr =
        locless (Call {
          fn = locless (Var "read_csv");
          args = [ (None, locless (Value (VString csv_path))) ];
        })
      in
      let csv_ty = Analyzer.infer_type scope csv_expr in
      Sys.remove csv_path;
      let cached_ty = Analyzer.infer_type scope csv_expr in
      (* Intentional: infer_type records observed columns as a side effect. *)
      ignore (Analyzer.infer_type scope (locless (ColumnRef "mpg")));
      let df_expr =
        locless (Call {
          fn = locless (Var "dataframe");
          args = [
            (None, locless (ListLit [
              (Some "a", locless (Value (VInt 1)));
              (Some "b", locless (Value (VInt 2)));
            ]));
          ];
        })
      in
      let stmt =
        {
          node =
            Assignment {
              name = "df2";
              typ = None;
              expr =
                locless (Call {
                  fn = locless (Var "mutate");
                  args = [
                    (None, df_expr);
                    (Some "c", locless (Value (VInt 3)));
                  ];
                });
            };
          loc = Some { file = None; line = 1; column = 1 };
        }
      in
      let analysis = Analyzer.analyze [ stmt ] scope in
      let defs_ok =
        match Analyzer.Definition_map.find_opt "df2" analysis.Analyzer.definitions with
        | Some { line; column; _ } -> line = 1 && column = 1
        | None -> false
      in
      let sym_ok =
        match Symbol_table.lookup scope "df2" with
        | Some { typ = Some (Semantic_type.TDataFrame cols); _ } ->
            List.map (fun c -> c.Semantic_type.name) cols = [ "c"; "a"; "b" ]
        | _ -> false
      in
      let csv_ok ty =
        match ty with
        | Semantic_type.TDataFrame cols -> List.map (fun c -> c.Semantic_type.name) cols = [ "a"; "b" ]
        | _ -> false
      in
      csv_ok csv_ty && csv_ok cached_ty && defs_ok && sym_ok
      && Symbol_table.get_observed_columns scope = [ "mpg" ])
  );
  print_newline ();

  Printf.printf "Coverage — Package manager helpers:\n";
  test_case "documentation_manager validates docs layouts" (fun () ->
    with_temp_dir "docs" (fun dir ->
      let missing_ok =
        match Documentation_manager.validate_docs dir with
        | Error _ -> true
        | Ok () -> false
      in
      let docs_dir = Filename.concat dir "docs" in
      Unix.mkdir docs_dir 0o755;
      write_text (Filename.concat docs_dir "index.md") "# Docs\n";
      missing_ok && Documentation_manager.validate_docs dir = Ok ())
  );
  test_case "release_manager validates versions and project files" (fun () ->
    with_temp_dir "release" (fun dir ->
      write_text (Filename.concat dir "DESCRIPTION.toml")
        {|
[package]
name = "pkg"
version = "1.2.3"

[dependencies]

[t]
min_version = "0.51.0"
|};
      write_text (Filename.concat dir "CHANGELOG.md") "## [1.2.3]\n- Added tests\n";
      let version_ok =
        match Release_manager.get_package_version dir with
        | Ok "1.2.3" -> true
        | _ -> false
      in
      let changelog_ok = Release_manager.validate_changelog dir "1.2.3" = Ok () in
      let missing_ok =
        match Release_manager.validate_changelog dir "9.9.9" with
        | Error _ -> true
        | Ok () -> false
      in
      let version_format_ok =
        Release_manager.validate_version_format "1.2.3-beta_1" = Ok ()
        &&
        match Release_manager.validate_version_format "1.2.3;rm" with
        | Error _ -> true
        | Ok () -> false
      in
      let argv_ok =
        match Release_manager.run_command_argv [| "sh"; "-c"; "printf release-ok" |] with
        | Ok "release-ok" -> true
        | _ -> false
      in
      version_ok && changelog_ok && missing_ok && version_format_ok && argv_ok)
  );
  test_case "test_discovery discovers tests and handles empty suites" (fun () ->
    with_temp_dir "discovery" (fun dir ->
      let tests_dir = Filename.concat dir "tests" in
      let nested = Filename.concat tests_dir "nested" in
      Unix.mkdir tests_dir 0o755;
      Unix.mkdir nested 0o755;
      write_text (Filename.concat tests_dir "test-alpha.t") "";
      write_text (Filename.concat nested "beta_test.t") "";
      write_text (Filename.concat tests_dir "ignore.t") "";
      let discovered = Test_discovery.discover_tests tests_dir in
      let file_ok =
        List.length discovered = 2
        && List.exists (fun p -> Filename.basename p = "test-alpha.t") discovered
        && List.exists (fun p -> Filename.basename p = "beta_test.t") discovered
      in
      let single_ok =
        match Test_discovery.run_test_file (Filename.concat tests_dir "test-alpha.t") with
        | { Test_discovery.success = true; error_msg = None; _ } -> true
        | _ -> false
      in
      let empty_suite =
        with_temp_dir "empty-suite" (fun empty_dir -> Test_discovery.run_suite empty_dir)
      in
      file_ok
      && single_ok
      && empty_suite.total = 0
      && Test_discovery.format_duration 0.0001 = "<1ms"
      && Test_discovery.format_duration 0.5 = "500ms"
      && Test_discovery.format_duration 1.25 = "1.25s")
  );
  print_newline ();

  Printf.printf "Coverage — Pipeline helpers:\n";
  test_case "nix_utils quoting and op rendering behave as expected" (fun () ->
    Nix_utils.op_to_string Formula = "~"
    && Nix_utils.shell_single_quote "a'b" = "'a'\"\\'\"'b'"
    && Nix_utils.nix_double_quote "a\"$\n" = "\"a\\\"\\$\\n\""
  );
  test_case "builder_utils filesystem and command helpers work" (fun () ->
    with_temp_dir "builder-utils" (fun dir ->
      let root = Filename.concat dir "project" in
      let nested = Filename.concat root "src/nested" in
      Unix.mkdir root 0o755;
      Unix.mkdir (Filename.concat root "src") 0o755;
      Unix.mkdir nested 0o755;
      write_text (Filename.concat root "dune-project") "(lang dune 3.0)\n";
      with_cwd nested (fun () ->
        Builder_utils.ensure_pipeline_dir ();
        ignore (Builder_utils.write_file "sample.txt" "hello\nworld\n");
        let first_line_ok = Builder_utils.read_file_first_line "sample.txt" = Some "hello" in
        let root_ok = Builder_utils.find_project_root (Sys.getcwd ()) = root in
        let rel_ok = Builder_utils.get_relative_path_to_root () = "../.." in
        let cmd_ok =
          match Builder_utils.run_command_capture "printf 'alpha\\n'" with
          | Ok (Unix.WEXITED 0, "alpha") -> true
          | _ -> false
        in
        let argv_ok =
          match Builder_utils.run_command_argv_capture [| "sh"; "-c"; "printf beta" |] with
          | Ok "beta" -> true
          | _ -> false
        in
        first_line_ok
        && Sys.file_exists Builder_utils.pipeline_dir
        && Builder_utils.command_exists "sh"
        && root_ok
        && rel_ok
        && cmd_ok
        && argv_ok
        && String.length (Builder_utils.get_timestamp ()) = 15))
  );
  test_case "builder_nix_store writes fallback env.nix outside nix store" (fun () ->
    with_temp_dir "env-nix" (fun dir ->
      with_cwd dir (fun () ->
        Builder_utils.ensure_pipeline_dir ();
        Builder_nix_store.write_env_nix ();
        let content = read_text Builder_utils.env_nix_path in
        String.contains content '[' && String.contains content ']'))
  );
  test_case "builder_inspect and builder_copy handle logs and artifacts" (fun () ->
    with_temp_dir "pipeline" (fun dir ->
      with_cwd dir (fun () ->
        Unix.mkdir Builder_utils.pipeline_dir 0o755;
        let source_dir = Filename.concat dir "artifacts/node1" in
        Unix.mkdir (Filename.concat dir "artifacts") 0o755;
        Unix.mkdir source_dir 0o755;
        write_text (Filename.concat source_dir "result.txt") "payload";
        write_text
          (Filename.concat Builder_utils.pipeline_dir "build_log_20240101.json")
          {|{"nodes":[{"node":"node1","runtime":"T","path":"artifacts/node1/result.txt","serializer":"json","class":"Artifact","dependencies":["dep_a"]}]}|};
        let inspect_ok =
          match Builder_inspect.inspect_pipeline () with
          | VDataFrame { arrow_table; _ } ->
              Arrow_table.num_rows arrow_table = 1
              && Arrow_table.column_names arrow_table
                 = [ "derivation"; "build_success"; "runtime"; "class"; "path"; "output" ]
          | _ -> false
        in
        let invalid_regex_ok =
          expect_error_code TypeError (Builder_inspect.inspect_pipeline ~which_log:"[" ())
        in
        let missing_drv_ok =
          expect_error_code FileError (Builder_inspect.read_node_log "node1")
        in
        let copy_ok =
          match Builder_copy.pipeline_copy ~target_dir:"pipeline-output" () with
          | VString msg ->
              String.starts_with ~prefix:"Successfully copied 1 node" msg
              && Sys.file_exists "pipeline-output/node1/result.txt"
          | _ -> false
        in
        let copy_missing_ok =
          expect_error_code KeyError
            (Builder_copy.pipeline_copy ~node_name:(Some "missing") ~target_dir:"pipeline-output-2" ())
        in
        let invalid_mode_ok =
          expect_error_code GenericError
            (Builder_copy.pipeline_copy ~dir_mode:"755" ())
        in
        inspect_ok && invalid_regex_ok && missing_drv_ok && copy_ok && copy_missing_ok && invalid_mode_ok))
  );
  print_newline ()
