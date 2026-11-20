(* tests/test_roadmap_features.ml *)
(* Unit tests for:
   1. pipeline_metrics & pipeline_metrics_markdown
   2. Lsp_support quick-fixes, pipeline bindings, UTF-16 offsets & live artifact hover
   3. Schema_check opt-in foreign node schema hydration
   4. T_formatter & t_fmt canonical formatter
   5. Provenance & t_provenance (RO-Crate 1.1, CycloneDX 1.5 SBOM, native JSON) *)

let run_tests pass_count fail_count failures _eval_string _eval_string_env _test test_env test_equal =
  Printf.printf "\n=== Roadmap Features (metrics, LSP, foreign schema, fmt, provenance) ===\n\n";
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

  let contains haystack needle =
    try ignore (Str.search_forward (Str.regexp_string needle) haystack 0); true
    with Not_found -> false
  in

  let mk_temp_dir prefix =
    let d = Filename.temp_file prefix ".d" in
    Sys.remove d;
    Unix.mkdir d 0o755;
    d
  in

  let write_file path content =
    let oc = open_out_bin path in
    Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
      output_string oc content)
  in

  let rec rm_rf path =
    if Sys.file_exists path then begin
      if Sys.is_directory path then begin
        Array.iter (fun f -> rm_rf (Filename.concat path f)) (Sys.readdir path);
        Unix.rmdir path
      end else Sys.remove path
    end
  in

  (* --- 1. pipeline_metrics & pipeline_metrics_markdown --- *)
  Printf.printf "1. pipeline_metrics:\n";
  test_equal env "pipeline_metrics empty pipeline has 0 rows"
    {|p = pipeline { a = 1 }; pipeline_metrics(p) |> nrow|}
    "0";
  test_equal env "pipeline_metrics sort_by on empty pipeline returns 0 rows"
    {|p = pipeline { a = 1 }; pipeline_metrics(p, sort_by = "aic") |> nrow|}
    "0";
  test_env env "pipeline_metrics rejects extra positional arg"
    {|p = pipeline { a = 1 }; pipeline_metrics(p, "time_series")|}
    "accepts only 1 positional argument";
  test_env env "pipeline_metrics rejects unknown named arg"
    {|p = pipeline { a = 1 }; pipeline_metrics(p, bogus = "x")|}
    "unknown argument `bogus`";
  test_env env "pipeline_metrics rejects non-Bool descending"
    {|p = pipeline { a = 1 }; pipeline_metrics(p, descending = "yes")|}
    "must be a Bool";
  test_env env "pipeline_metrics_markdown empty has header"
    {|p = pipeline { a = 1 }; pipeline_metrics_markdown(p)|}
    "| name | runtime | kind | task | method | n_obs | status |";

  let rows = List.filter_map Fun.id [
    Pipeline_metrics.model_row_of_meta
      ~name:"r_arima" ~runtime:"R" ~status:(Some "Completed")
      [("kind", `String "model"); ("task", `String "time_series");
       ("method", `String "ARIMA"); ("n_obs", `Int 144);
       ("metrics", `Assoc [("aic", `Float 1020.5); ("loglik", `Float (-505.2)); ("n_obs", `Float 999.0)])];
    Pipeline_metrics.model_row_of_meta
      ~name:"py_arima" ~runtime:"Python" ~status:(Some "Completed")
      [("kind", `String "model"); ("task", `String "time_series");
       ("method", `String "ARIMA"); ("n_obs", `Int 144);
       ("metrics", `Assoc [("aic", `Float 990.1); ("bic", `Float 1002.0)])];
    Pipeline_metrics.model_row_of_meta
      ~name:"r_lm" ~runtime:"R" ~status:(Some "Completed")
      [("kind", `String "model"); ("task", `String "regression");
       ("method", `String "lm"); ("n_obs", `Int 32);
       ("metrics", `Assoc [("r2", `Float 0.85)])];
  ] in
  let ts_rows = Pipeline_metrics.filter_by_task (Some "time_series") rows in
  check "pipeline_metrics filters by task" (List.length ts_rows = 2);
  let keys = Pipeline_metrics.metric_keys_of_rows ts_rows in
  check "pipeline_metrics prefixes colliding metric key n_obs -> metric_n_obs"
    (keys = ["aic"; "bic"; "loglik"; "metric_n_obs"]);
  (match Pipeline_metrics.sort_rows ~metric_keys:keys ~sort_by:(Some "aic") ~descending:false ts_rows with
   | Ok (first :: _) -> check "pipeline_metrics sorts lowest aic first" (first.mr_name = "py_arima")
   | _ -> check "pipeline_metrics sorts lowest aic first" false);
  let md = Pipeline_metrics.render_markdown_of_rows ~metric_keys:keys ts_rows in
  check "pipeline_metrics_markdown renders metric headers and values"
    (contains md "| aic | bic | loglik | metric_n_obs |" && contains md "py_arima" && contains md "990.1");

  (* --- 2. LSP quick-fixes & live artifact hover --- *)
  Printf.printf "\n2. LSP quick-fixes & live artifact hover:\n";
  let union_src = "type Tree = Leaf | Branch(Leaf)\n" in
  let union_diags = Lsp_support.static_diagnostics_of_text ~filename:"test.t" union_src in
  let union_qfs =
    Lsp_support.quick_fixes_for_range ~text:union_src ~range_start_line:0 ~range_end_line:0 union_diags
  in
  check "LSP quick-fix detects bare union case on line 0"
    (match union_qfs with
     | [{ qf_title; qf_edits = [{ start_line = 0; start_char = 12; end_line = 0; end_char = 16; new_text = "Leaf()" }] }] ->
         contains qf_title "Leaf"
     | _ -> false);

  let read_log_src = "p = pipeline { a = 1 }\nx = read_log(\"a\")\n" in
  let rl_diags = Lsp_support.static_diagnostics_of_text ~filename:"test.t" read_log_src in
  let rl_qfs =
    Lsp_support.quick_fixes_for_range ~text:read_log_src ~range_start_line:1 ~range_end_line:1 rl_diags
  in
  check "LSP quick-fix rewrites read_log(\"a\") to p.a"
    (match rl_qfs with
     | [{ qf_edits = [{ start_line = 1; new_text = "p.a"; _ }]; _ }] -> true
     | _ -> false);

  check "LSP extract_dot_member parses p.r_arima"
    (Lsp_support.extract_dot_member "x = read_node(p.r_arima)" 18 = Some ("p", "r_arima"));
  check "LSP extract_dot_member rejects float literal 1.5"
    (Lsp_support.extract_dot_member "x = 1.5" 6 = None);
  check "LSP extract_dot_member ignores text inside string literal"
    (Lsp_support.extract_dot_member {|x = "p.r_arima"|} 9 = None);
  check "LSP extract_dot_member ignores text inside comment"
    (Lsp_support.extract_dot_member "-- p.r_arima" 8 = None);
  check "LSP offset_to_line_char counts UTF-16 units for multi-byte UTF-8"
    (Lsp_support.offset_to_line_char "é = a" 5 = (0, 4));
  let prog_pipes =
    let lexbuf = Lexing.from_string "p = pipeline { a = 1 }\ndf = read_csv(\"x.csv\")\n" in
    Lsp_support.pipeline_bindings_of_program (Parser.program Lexer.token lexbuf)
  in
  check "LSP pipeline_bindings_of_program tracks only pipeline variables"
    (prog_pipes = ["p"]);

  let lsp_dir = mk_temp_dir "t_lsp_hover" in
  Fun.protect ~finally:(fun () -> rm_rf lsp_dir) (fun () ->
    let pipe_dir = Filename.concat lsp_dir "_pipeline" in
    Unix.mkdir pipe_dir 0o755;
    let art_dir = Filename.concat lsp_dir "art_r_arima" in
    Unix.mkdir art_dir 0o755;
    let art_file = Filename.concat art_dir "artifact" in
    write_file art_file "rds";
    write_file (Filename.concat art_dir "meta")
      {|{"kind":"model","task":"time_series","method":"ARIMA","n_obs":144,"metrics":{"aic":1015.2}}|};
    write_file (Filename.concat pipe_dir "build_log_20261120_120000_abc.json")
      (Printf.sprintf
         {|{"nodes":[{"node":"r_arima","runtime":"R","serializer":"default","status":"Completed","class":"Arima","path":"%s"}]}|}
         art_file);
    let hover =
      Lsp_support.artifact_hover_markdown
        ~file_path:(Filename.concat lsp_dir "pipeline.t")
        ~node_name:"r_arima"
    in
    check "LSP artifact_hover_markdown renders live status and foreign_meta"
      (match hover with
       | Some md ->
           contains md "Pipeline Node `r_arima`"
           && contains md "`Completed`"
           && contains md "`time_series`"
           && contains md "aic=1015"
       | None -> false)
  );

  (* --- 3. Schema_check opt-in foreign node schema hydration --- *)
  Printf.printf "\n3. Schema_check foreign node hydration:\n";
  let parsed_meta_schema =
    Schema_check.schema_of_meta_json
      {|{"kind":"frame","columns":["mpg","wt","cyl","ts"],"dtypes":{"mpg":"numeric","cyl":"integer","ts":"datetime64[ns]"}}|}
  in
  check "schema_of_meta_json extracts columns, normalizes known dtypes, maps unknown to None"
    (match parsed_meta_schema with
     | Some cols ->
         Schema_check.schema_names cols = ["mpg"; "wt"; "cyl"; "ts"]
         && Schema_check.schema_find_type "mpg" cols = Some "double"
         && Schema_check.schema_find_type "cyl" cols = Some "int"
         && Schema_check.schema_find_type "ts" cols = None
     | None -> false);

  let schema_dir = mk_temp_dir "t_foreign_schema" in
  Fun.protect ~finally:(fun () -> rm_rf schema_dir) (fun () ->
    let pipe_dir = Filename.concat schema_dir "_pipeline" in
    Unix.mkdir pipe_dir 0o755;
    let art_dir = Filename.concat schema_dir "art_r_clean" in
    Unix.mkdir art_dir 0o755;
    let art_file = Filename.concat art_dir "artifact" in
    write_file art_file "ipc";
    write_file (Filename.concat art_dir "meta")
      {|{"kind":"frame","columns":["mpg","wt","hp"],"dtypes":{"mpg":"double","wt":"double"}}|};
    write_file (Filename.concat pipe_dir "build_log_20261120_120000_xyz.json")
      (Printf.sprintf
         {|{"nodes":[{"node":"r_clean","runtime":"R","serializer":"ipc","status":"Completed","path":"%s"}]}|}
         art_file);
    let script_path = Filename.concat schema_dir "pipe.t" in
    write_file script_path
      "p = pipeline {\n  r_clean = rn(command = <{ mtcars }>, serializer = ^ipc)\n  bad = r_clean |> filter($mgg > 20)\n}\n";
    let res_static = Check_utils.run_check ~schema:true ~hydrate_foreign:false Typecheck.Strict script_path (Packages.init_env ()) in
    check "default t check --schema stays strictly static (no _pipeline/ reads)"
      (not (List.exists (fun (d : Diagnostics.diagnostic) -> d.diag_error_class = Diagnostics.Schema_mismatch)
              (Diagnostics.check_result_entries res_static)));
    let res_hydrated = Check_utils.run_check ~schema:true ~hydrate_foreign:true Typecheck.Strict script_path (Packages.init_env ()) in
    let diags = Diagnostics.check_result_entries res_hydrated in
    check "t check --schema --hydrate-foreign catches column typo downstream of foreign R node"
      (List.exists (fun (d : Diagnostics.diagnostic) ->
         d.diag_error_class = Diagnostics.Schema_mismatch
         && contains d.diag_message "mgg"
         && contains d.diag_message "mpg") diags)
  );

  (* --- 4. T_formatter & t_fmt --- *)
  Printf.printf "\n4. T_formatter & t_fmt:\n";
  let check_fmt name input expected =
    match T_formatter.format_string input with
    | Ok got -> check name (got = expected)
    | Error _ -> check name false
  in
  check_fmt "T_formatter keeps space around string |> fn"
    "\"a\" |> f\n" "\"a\" |> f\n";
  check_fmt "T_formatter inserts space in \"a\"==x"
    "\"a\"==x\n" "\"a\" == x\n";
  check_fmt "T_formatter inserts space in x=\"foo\""
    "x=\"foo\"\n" "x = \"foo\"\n";
  check_fmt "T_formatter inserts space in f(a,\"b\")"
    "f(a,\"b\")\n" "f(a, \"b\")\n";
  check_fmt "T_formatter keeps space after inline raw block <{ x }> |> g"
    "<{ x }>|>g\n" "<{ x }> |> g\n";
  check_fmt "T_formatter normalizes binary + and keeps unary -"
    "x=1+2\ny=-5\n" "x = 1 + 2\ny = -5\n";
  check_fmt "T_formatter preserves CRLF line endings"
    "x = 1\r\ny = 2\r\n" "x = 1\r\ny = 2\r\n";

  let messy =
    "x=1+2\n\n\n-- keep comment\np = pipeline{\nraw = rn(\ncommand = <{\n  # untouched R   code\n  x<-1+2\n}>,\nserializer=^ipc\n)\nclean = raw\n|>filter($mpg==20)\n|>select($mpg,$wt)\n}\n"
  in
  (match T_formatter.format_string messy with
   | Error msg ->
       check ("T_formatter formats valid T code (" ^ msg ^ ")") false
   | Ok formatted ->
       check "T_formatter preserves comment" (contains formatted "-- keep comment");
       check "T_formatter preserves raw R block verbatim" (contains formatted "  # untouched R   code\n  x<-1+2\n");
       check "T_formatter normalizes arithmetic spacing" (contains formatted "x = 1 + 2");
       check "T_formatter indents pipe continuations" (contains formatted "    |> filter($mpg == 20)");
       check "T_formatter collapses multiple blank lines" (not (contains formatted "\n\n\n"));
       (match T_formatter.format_string formatted with
        | Ok formatted2 -> check "T_formatter is idempotent" (formatted2 = formatted)
        | Error _ -> check "T_formatter is idempotent" false));

  let fmt_dir = mk_temp_dir "t_fmt_test" in
  Fun.protect ~finally:(fun () -> rm_rf fmt_dir) (fun () ->
    let fpath = Filename.concat fmt_dir "sample.t" in
    write_file fpath "x=1\n";
    test_equal env "t_fmt check=true false on unformatted file"
      (Printf.sprintf {|t_fmt("%s", check = true)|} fpath)
      "false";
    let _ = _eval_string_env (Printf.sprintf {|t_fmt("%s", write = true)|} fpath) env in
    test_equal env "t_fmt check=true true after write=true"
      (Printf.sprintf {|t_fmt("%s", check = true)|} fpath)
      "true"
  );

  (* --- 5. Provenance & t_provenance --- *)
  Printf.printf "\n5. Provenance & t_provenance:\n";
  (* Known SHA-256 of empty bytes: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
     Base64 SRI: sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU= *)
  let empty_sri = "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=" in
  check "sri_sha256_to_hex decodes SRI base64 to 64-char hex"
    (Provenance.sri_sha256_to_hex empty_sri
     = Some "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  check "sanitize_purl_name strips PEP-440 specifiers"
    (Provenance.sanitize_purl_name "pandas>=2.0,<3.0" = "pandas");

  let prov_dir = mk_temp_dir "t_prov_test" in
  Fun.protect ~finally:(fun () -> rm_rf prov_dir) (fun () ->
    let src_dir = Filename.concat prov_dir "src" in
    let pipe_dir = Filename.concat prov_dir "_pipeline" in
    let art_dir = Filename.concat prov_dir "art_m" in
    Unix.mkdir src_dir 0o755;
    Unix.mkdir pipe_dir 0o755;
    Unix.mkdir art_dir 0o755;
    write_file (Filename.concat prov_dir "tproject.toml")
      "[project]\nname = \"demo_proj\"\nversion = \"1.2.3\"\ndescription = \"Audit test\"\nlicense = \"MIT\"\n\n[r-dependencies]\npackages = [\"forecast\"]\n\n[py-dependencies]\npackages = [\"statsmodels>=0.14\", \"statsmodels>=0.14\"]\n";
    write_file (Filename.concat prov_dir "flake.lock")
      (Printf.sprintf
         {|{"nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs"}},"nixpkgs":{"locked":{"type":"github","owner":"NixOS","repo":"nixpkgs","rev":"abc123","narHash":"%s","lastModified":1700000000}}},"version":7}|}
         empty_sri);
    let art_file = Filename.concat art_dir "artifact" in
    write_file art_file "rds";
    write_file (Filename.concat art_dir "meta") {|{"kind":"model","task":"time_series","metrics":{"aic":123.4}}|};
    write_file (Filename.concat pipe_dir "build_log_20261120_120000_prv.json")
      (Printf.sprintf {|{"nodes":[{"node":"m1","runtime":"R","serializer":"default","status":"Completed","path":"%s","dependencies":[]}]}|} art_file);
    write_file (Filename.concat src_dir "pipeline.t")
      "meta = intent { goal: \"Forecast monthly passengers\", owner: \"team\" }\n";

    (match Provenance.generate ~dir:prov_dir ~format:"ro-crate" () with
     | Ok s ->
         check "RO-Crate 1.1 has context, datePublished, license, mentions, CreateAction, and intent"
           (contains s "https://w3id.org/ro/crate/1.1/context"
            && contains s "\"datePublished\""
            && contains s "\"MIT\""
            && contains s "\"mentions\""
            && contains s "\"CreateAction\""
            && contains s "#node-m1"
            && contains s "Forecast monthly passengers")
     | Error _ -> check "RO-Crate generation succeeds" false);

    (match Provenance.generate ~dir:prov_dir ~format:"ro-crate" ~include_meta:false () with
     | Ok s -> check "RO-Crate include_meta=false omits foreignMeta" (not (contains s "foreignMeta"))
     | Error _ -> check "RO-Crate include_meta=false succeeds" false);

    (match Provenance.generate ~dir:prov_dir ~format:"sbom" () with
     | Ok s ->
         let json = Yojson.Safe.from_string s in
         let open Yojson.Safe.Util in
         let comps = json |> member "components" |> to_list in
         let bom_refs = List.map (fun c -> c |> member "bom-ref" |> to_string) comps in
         let unique_refs = List.sort_uniq String.compare bom_refs in
         let deps = json |> member "dependencies" |> to_list in
         let all_dep_refs_valid =
           List.for_all (fun d ->
             let r = d |> member "ref" |> to_string in
             List.mem r bom_refs
             && List.for_all (fun x -> List.mem (to_string x) bom_refs) (d |> member "dependsOn" |> to_list)
           ) deps
         in
         check "SBOM emits hex SHA-256, sanitized purls, unique bom-refs, and no dangling dep refs"
           (contains s "\"CycloneDX\""
            && contains s "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            && contains s "pkg:cran/forecast"
            && contains s "pkg:pypi/statsmodels"
            && not (contains s ">=0.14")
            && List.length bom_refs = List.length unique_refs
            && all_dep_refs_valid)
     | Error _ -> check "SBOM generation succeeds" false);

    let out_file = Filename.concat prov_dir "bundle.json" in
    test_env env "t_provenance writes bundle and returns JSON"
      (Printf.sprintf {|t_provenance(format = "json", output = "%s", dir = "%s")|} out_file prov_dir)
      "demo_proj";
    check "t_provenance wrote output file" (Sys.file_exists out_file);
    test_env env "t_provenance rejects unknown format"
      (Printf.sprintf {|t_provenance(format = "xml", dir = "%s")|} prov_dir)
      "Unknown provenance format"
  );

  print_newline ()
