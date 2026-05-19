(* tests/test_serializers.ml *)
open Ast

let capture_stderr f =
  let stderr_fd = Unix.descr_of_out_channel stderr in
  let saved_stderr = Unix.dup stderr_fd in
  let read_fd, write_fd = Unix.pipe () in
  let restored = ref false in
  let close_noerr fd =
    try Unix.close fd with
    | Unix.Unix_error _ -> ()
  in
  let restore () =
    if not !restored then begin
      restored := true;
      flush stderr;
      Unix.dup2 saved_stderr stderr_fd;
      close_noerr saved_stderr
    end
  in
  Fun.protect
    ~finally:(fun () ->
      restore ();
      close_noerr read_fd;
      close_noerr write_fd)
    (fun () ->
      Unix.dup2 write_fd stderr_fd;
      close_noerr write_fd;
      let result = f () in
      restore ();
      let buffer = Buffer.create 128 in
      let chunk = Bytes.create 256 in
      let rec drain () =
        match Unix.read read_fd chunk 0 (Bytes.length chunk) with
        | 0 -> ()
        | n ->
            Buffer.add_subbytes buffer chunk 0 n;
            drain ()
      in
      drain ();
      (result, Buffer.contents buffer))

let run_tests pass_count fail_count failures _eval_string eval_string_env _test =
  Printf.printf "First-Class Serializers:\n";

  let contains s sub = 
    try ignore (Str.search_forward (Str.regexp_string sub) s 0); true
    with Not_found -> false
  in
  let contains_all s needles =
    List.for_all (fun needle -> contains s needle) needles
  in
  let omits_all s needles =
    List.for_all (fun needle -> not (contains s needle)) needles
  in
  let has_no_implicit_serializer_pkgs s =
    omits_all s
      [
        "pkgs.rPackages.jsonlite";
        "pkgs.rPackages.arrow";
        "pkgs.rPackages.r2pmml";
        "pkgs.rPackages.XML";
        "ps.pandas";
        "ps.pyarrow";
        "ps.sklearn2pmml";
        "ps.scikit-learn";
        "ps.scipy";
        "ps.numpy";
        "ps.statsmodels";
        "pkgs.jre";
        "pkgs.quarto";
        "pkgs.which";
        "pkgs.rPackages.knitr";
        "pkgs.rPackages.rmarkdown";
      ]
  in

  (* 1. Built-in Registry Resolution *)
  let (v, _) = eval_string_env {| ^csv |} (Packages.init_env ()) in
  (match v with
   | VSerializer s when s.s_format = "csv" ->
       incr pass_count; Printf.printf "  ✓ ^csv resolves to serializer record\n"
   | _ ->
       incr fail_count; failures := "  ✗ ^csv resolution failed\n" :: !failures; Printf.printf "  ✗ ^csv resolution failed\n") ;

  let (v, _) = eval_string_env {| ^arrow |} (Packages.init_env ()) in
  (match v with
   | VSerializer s when s.s_format = "arrow" ->
       incr pass_count; Printf.printf "  ✓ ^arrow resolves to serializer record\n"
   | _ ->
       incr fail_count; failures := "  ✗ ^arrow resolution failed\n" :: !failures; Printf.printf "  ✗ ^arrow resolution failed\n") ;

  (* ONNX serializer resolution *)
  let (v, _) = eval_string_env {| ^onnx |} (Packages.init_env ()) in
  (match v with
   | VSerializer s when s.s_format = "onnx" ->
       incr pass_count; Printf.printf "  ✓ ^onnx resolves to serializer record\n"
   | _ ->
       incr fail_count; failures := "  ✗ ^onnx resolution failed\n" :: !failures; Printf.printf "  ✗ ^onnx resolution failed\n") ;

  (* ONNX serializer has correct R/Python/Julia helpers *)
  let (v, _) = eval_string_env {| ^onnx |} (Packages.init_env ()) in
  (match v with
   | VSerializer s when s.s_r_writer = Some "r_write_onnx"
                       && s.s_r_reader = Some "r_read_onnx"
                       && s.s_py_writer = Some "py_write_onnx"
                       && s.s_py_reader = Some "py_read_onnx"
                       && s.s_julia_writer = Some "jl_write_onnx"
                       && s.s_julia_reader = Some "jl_read_onnx" ->
       incr pass_count; Printf.printf "  ✓ ^onnx has correct R/Python/Julia helper names\n"
    | _ ->
       incr fail_count; failures := "  ✗ ^onnx R/Python/Julia helper names incorrect\n" :: !failures; Printf.printf "  ✗ ^onnx R/Python/Julia helper names incorrect\n") ;

  (* ONNX placeholder writer throws descriptive error *)
  let (v, _) = eval_string_env {| (^onnx).writer("test.onnx", 1) |} (Packages.init_env ()) in
  (match v with
   | VError { message; _ } when contains message "does not have a T-native implementation yet" ->
       incr pass_count; Printf.printf "  ✓ ^onnx placeholder writer throws descriptive error\n"
   | _ ->
       incr fail_count; failures := "  ✗ ^onnx placeholder writer failed to throw error\n" :: !failures; Printf.printf "  ✗ ^onnx placeholder writer failed to throw error\n") ;

  (* 2. Custom Serializers *)
  let env = Packages.init_env () in
  let (_, env) = eval_string_env {|
    my_ser = [
      format: "custom",
      writer: \(path, val) { print("writing"); Ok(NA) },
      reader: \(path) { Ok(42) },
      r_writer: <{ function(obj, path) { saveRDS(obj, path) } }>,
      py_writer: <{ lambda obj, path: pickle.dump(obj, open(path, 'wb')) }>
    ]
  |} env in
  let (v, _) = eval_string_env {| type(my_ser) |} env in
  if Ast.Utils.value_to_string v = {|"Dict"|} then begin
    incr pass_count; Printf.printf "  ✓ Custom serializer with foreign snippets (mock)\n"
  end else begin
    incr fail_count; failures := "  ✗ Custom serializer mock failed\n" :: !failures; Printf.printf "  ✗ Custom serializer mock failed\n"
  end;

  (* 3. Static Coherence Checks - Mismatch *)
  let env_coh = Packages.init_env () in
  let (v, _) = eval_string_env {|
    p = pipeline {
       a = node(command = <{ 1 }>, serializer = ^csv)
       b = node(command = <{ a + 1 }>, deserializer = ^arrow)
    }
    populate_pipeline(p)
  |} env_coh in
  (match v with
   | VError { message; _ } when contains message "Serializer coherence error" ->
       incr pass_count; Printf.printf "  ✓ Static coherence check detects format mismatch\n"
   | other ->
       incr fail_count; 
       Printf.printf "  ✗ Static coherence check failed to catch mismatch. Got: %s\n" 
         (Ast.Utils.value_to_string other));

  (* 4. Static Coherence Checks - Match *)
  let env_match = Packages.init_env () in
  let (v, _) = eval_string_env {|
    p = pipeline {
       a = node(command = <{ 1 }>, serializer = ^arrow)
       b = node(command = <{ a + 1 }>, deserializer = ^arrow)
    }
    populate_pipeline(p)
  |} env_match in
  (match v with
   | VString _ -> 
       incr pass_count; Printf.printf "  ✓ Static coherence check accepts matching formats\n"
   | other -> 
       incr fail_count;
        let msg = Printf.sprintf "  ✗ Static coherence check failed on matching formats. Got: %s\n" (Ast.Utils.value_to_string other) in
        failures := msg :: !failures;
        Printf.printf "%s" msg);

  (* 4b. Explicit dependency checks happen before pipeline emission/build.
     These must run from a temp dir that has NO tproject.toml so that
     ensure_project_requirements cannot find the repo's tproject.toml
     (which already declares all the packages) and return Ok () instead
     of the expected StructuralError. *)
  let with_empty_dir f =
    let tmp = Filename.get_temp_dir_name () in
    let dir = Printf.sprintf "%s/tlang-dep-check-%d" tmp (Unix.getpid ()) in
    (try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
    let old_cwd = Sys.getcwd () in
    Fun.protect
      ~finally:(fun () ->
        Sys.chdir old_cwd;
        ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir))))
      (fun () -> Sys.chdir dir; f ())
  in

  (with_empty_dir (fun () ->
    let env_onnx_builtin = Packages.init_env () in
    let ((v, _), warnings) =
      capture_stderr (fun () ->
        eval_string_env {|
          p = pipeline {
             model = node(command = <{ 1 }>, serializer = ^onnx)
          }
          populate_pipeline(p)
        |} env_onnx_builtin)
    in
    match v with
    | VString _ when not (contains warnings "custom or unknown strategy") ->
        incr pass_count;
        Printf.printf "  ✓ Built-in ^onnx serializer does not emit custom strategy warning\n"
    | other ->
        incr fail_count;
        Printf.printf "  ✗ Built-in ^onnx serializer warning handling failed. Got: %s; warnings: %S\n"
          (Ast.Utils.value_to_string other) warnings));

  (with_empty_dir (fun () ->
    let env_onnx = Packages.init_env () in
    let (v, _) = eval_string_env {|
      p = pipeline {
         model = node(command = <{ 1 }>, runtime = Python, serializer = ^onnx)
      }
      populate_pipeline(p)
    |} env_onnx in
    match v with
    | VError { code; message; _ }
      when code = StructuralError
        && contains_all message
             [ "tproject.toml"; "onnxruntime"; "skl2onnx" ] ->
        incr pass_count;
        Printf.printf "  ✓ Missing serializer dependencies fail statically without implicit injection\n"
    | other ->
        incr fail_count;
        Printf.printf "  ✗ Explicit dependency check failed for ONNX pipeline. Got: %s\n"
          (Ast.Utils.value_to_string other)));

  (with_empty_dir (fun () ->
    let env_pmml_deps = Packages.init_env () in
    let (v, _) = eval_string_env {|
      p = pipeline {
         model = node(command = <{ 1 }>, runtime = Python, deserializer = ^pmml)
      }
      populate_pipeline(p)
    |} env_pmml_deps in
    match v with
    | VError { code; message; _ }
      when code = StructuralError
        && contains_all message
             [ "tproject.toml"; "pyarrow"; "sklearn2pmml" ] ->
        incr pass_count;
        Printf.printf "  ✓ Missing PMML dependencies fail statically with explicit pyarrow guidance\n"
    | other ->
         incr fail_count;
         Printf.printf "  ✗ Explicit dependency check failed for PMML pipeline. Got: %s\n"
           (Ast.Utils.value_to_string other)));

  (with_empty_dir (fun () ->
    let env_julia_onnx = Packages.init_env () in
    let (v, _) = eval_string_env {|
      p = pipeline {
         model = node(command = <{ 1 }>, runtime = Julia, deserializer = ^onnx)
      }
      populate_pipeline(p)
    |} env_julia_onnx in
    match v with
    | VError { code; message; _ }
      when code = StructuralError
        && contains_all message
             [ "tproject.toml"; "ONNXRunTime" ] ->
        incr pass_count;
        Printf.printf "  ✓ Missing Julia ONNX dependencies fail statically with explicit ONNXRunTime guidance\n"
    | other ->
        incr fail_count;
        Printf.printf "  ✗ Explicit dependency check failed for Julia ONNX pipeline. Got: %s\n"
          (Ast.Utils.value_to_string other)));

  (* 4c. Nix emission no longer injects serializer/quarto packages implicitly *)
  let env_emit = Packages.init_env () in
  let (v, _) = eval_string_env {|
    p = pipeline {
       json_r = node(command = <{ 1 }>, runtime = R, serializer = ^json)
       csv_py = node(command = <{ 1 }>, runtime = Python, serializer = ^csv)
       arrow_py = node(command = <{ 1 }>, runtime = Python, serializer = ^arrow)
       pmml_py = node(command = <{ 1 }>, runtime = Python, serializer = ^pmml)
       model = node(command = <{ 1 }>, runtime = Python, serializer = ^onnx)
       report = node(script = "report.qmd")
    }
    p
  |} env_emit in
  (match v with
   | VPipeline p ->
       let nix = Nix_emitter.emit_pipeline p in
       if has_no_implicit_serializer_pkgs nix
       then begin
         incr pass_count; Printf.printf "  ✓ Pipeline Nix emission keeps built-in serializer dependencies explicit\n"
       end else begin
         incr fail_count; failures := "  ✗ Pipeline Nix emission still injects serializer dependencies implicitly\n" :: !failures; Printf.printf "  ✗ Pipeline Nix emission still injects serializer dependencies implicitly\n"
       end
   | other ->
       incr fail_count;
       Printf.printf "  ✗ Failed to build pipeline for Nix emission test. Got: %s\n"
         (Ast.Utils.value_to_string other));

  (* 4d. Python PMML reader surfaces a descriptive dependency error *)
  let env_pmml = Packages.init_env () in
  let (v, _) = eval_string_env {|
    p = pipeline {
       pmml_py = node(command = <{ 1 }>, runtime = Python, deserializer = ^pmml)
    }
    p
  |} env_pmml in
  (match v with
   | VPipeline p ->
       let nix = Nix_emitter.emit_pipeline p in
       if contains_all nix
            [
              "class JPMMLModel:";
              "subprocess.run([";
              "\"java\", \"-jar\", jar_path";
              "--pmml";
            ]
          && not (contains nix "from pypmml import Model")
       then begin
         incr pass_count; Printf.printf "  ✓ Python PMML reader uses JPMML-backed implementation\n"
       end else begin
         incr fail_count; failures := "  ✗ Python PMML reader failed to use JPMML-backed implementation\n" :: !failures; Printf.printf "  ✗ Python PMML reader failed to use JPMML-backed implementation\n"
       end
   | other ->
       incr fail_count;
       Printf.printf "  ✗ Failed to build PMML pipeline for reader emission test. Got: %s\n"
          (Ast.Utils.value_to_string other));

  let env_julia_emit = Packages.init_env () in
  let (v, _) = eval_string_env {|
    p = pipeline {
       model = node(command = <{ 1 }>, runtime = Julia, deserializer = ^onnx)
    }
    p
  |} env_julia_emit in
  (match v with
   | VPipeline p ->
         let nix = Nix_emitter.emit_pipeline p in
         let expected = [
                "import ONNXRunTime as ORT";
               "ORT.load_inference(path)";
               "jl_read_onnx";
               "jl_write_onnx";
               "using ONNX";
               "ONNX.save(path, model)";
               "mutable struct TCaptureLogger <: AbstractLogger";
               "jl_write_error(e, joinpath(ENV[\\\"out\\\"], \\\"artifact\\\"))";
               "jl_write_warnings(captured_logger.warnings, joinpath(ENV[\\\"out\\\"], \\\"warnings\\\"))";
               "write(f, \"VError\")";
               "with_logger(captured_logger) do";
               "Base.invokelatest(__tlang_node_thunk)"
             ] in
        let missing = List.filter (fun s -> not (contains nix s)) expected in
        if missing = [] then begin
          incr pass_count; Printf.printf "  ✓ Julia helper injection captures structured errors and warnings\n"
        end else begin
          incr fail_count;
          let msg = Printf.sprintf "  ✗ Julia helper injection missing from emitted Nix. Missing strings: %s\n" (String.concat ", " missing) in
          failures := msg :: !failures;
          Printf.printf "%s" msg
        end
    | other ->
        incr fail_count;
        Printf.printf "  ✗ Failed to build Julia diagnostics pipeline for emission test. Got: %s\n"
          (Ast.Utils.value_to_string other));

  let env_julia_pmml_emit = Packages.init_env () in
  let (v, _) = eval_string_env {|
    p = pipeline {
       model = node(command = <{ 1 }>, runtime = Julia, serializer = ^pmml)
    }
    p
  |} env_julia_pmml_emit in
  (match v with
   | VPipeline p ->
        let nix = Nix_emitter.emit_pipeline p in
        if contains_all nix
             [
               "collect(stderror(model))";
               "format_std_error_attr(value) = isnan(value) ? \"\" : \" stdError=\\\"$value\\\"\"";
               "RegressionTable intercept=\\\"$intercept\\\"$(format_std_error_attr(intercept_std_error))";
               "NumericPredictor name=\\\"$name\\\" coefficient=\\\"$val\\\"$(format_std_error_attr(std_err))";
             ]
        then begin
          incr pass_count; Printf.printf "  ✓ Julia PMML writer emits coefficient standard errors\n"
        end else begin
          incr fail_count; failures := "  ✗ Julia PMML writer did not emit coefficient standard errors\n" :: !failures; Printf.printf "  ✗ Julia PMML writer did not emit coefficient standard errors\n"
        end
   | other ->
       incr fail_count;
       Printf.printf "  ✗ Failed to build Julia PMML pipeline for emission test. Got: %s\n"
         (Ast.Utils.value_to_string other));

  (* 5. Robustness: Placeholder error *)
  let (v, _) = eval_string_env {| (^csv).writer("test.csv", 1) |} (Packages.init_env ()) in
  (match v with
   | VError { message; _ } when contains message "does not have a T-native implementation yet" ->
       incr pass_count; Printf.printf "  ✓ Placeholder writer throws descriptive error\n"
   | _ ->
       incr fail_count; failures := "  ✗ Placeholder writer failed to throw error\n" :: !failures; Printf.printf "  ✗ Placeholder writer failed to throw error\n") ;

  (* 6. Invalid Identifiers *)
  let (v, _) = eval_string_env {| ^non_existent |} (Packages.init_env ()) in
  (match v with
   | VSymbol "^non_existent" ->
       incr pass_count; Printf.printf "  ✓ Invalid identifier resolves to symbol\n"
   | _ ->
       incr fail_count; failures := "  ✗ Invalid identifier failed\n" :: !failures; Printf.printf "  ✗ Invalid identifier failed\n") ;

  (* 7. Rejection of plain strings in polyglot snippets *)
  let (v, _) = eval_string_env {| 
    [ format: "custom", r_writer: "not a code block" ] 
  |} (Packages.init_env ()) in
  (match v with
   | VDict pairs ->
       (match List.assoc_opt "r_writer" pairs with
        | Some (VString _) -> 
            incr pass_count; Printf.printf "  ✓ Dict accurately stores VString for snippets (awaiting emitter rejection)\n"
        | _ -> 
            incr fail_count; failures := "  ✗ Dict failed to store VString for sniperts\n" :: !failures; Printf.printf "  ✗ Dict failed to store VString for sniperts\n")
   | _ -> 
       incr fail_count; failures := "  ✗ Snippet rejection test setup failed\n" :: !failures; Printf.printf "  ✗ Snippet rejection test setup failed\n");

  print_newline ()
