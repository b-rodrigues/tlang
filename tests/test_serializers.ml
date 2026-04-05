(* tests/test_serializers.ml *)
open Ast

let run_tests pass_count fail_count _eval_string eval_string_env _test =
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
       incr fail_count; Printf.printf "  ✗ ^csv resolution failed\n") ;

  let (v, _) = eval_string_env {| ^arrow |} (Packages.init_env ()) in
  (match v with
   | VSerializer s when s.s_format = "arrow" ->
       incr pass_count; Printf.printf "  ✓ ^arrow resolves to serializer record\n"
   | _ ->
       incr fail_count; Printf.printf "  ✗ ^arrow resolution failed\n") ;

  (* ONNX serializer resolution *)
  let (v, _) = eval_string_env {| ^onnx |} (Packages.init_env ()) in
  (match v with
   | VSerializer s when s.s_format = "onnx" ->
       incr pass_count; Printf.printf "  ✓ ^onnx resolves to serializer record\n"
   | _ ->
       incr fail_count; Printf.printf "  ✗ ^onnx resolution failed\n") ;

  (* ONNX serializer has correct R/Python helpers *)
  let (v, _) = eval_string_env {| ^onnx |} (Packages.init_env ()) in
  (match v with
   | VSerializer s when s.s_r_writer = Some "r_write_onnx"
                      && s.s_r_reader = Some "r_read_onnx"
                      && s.s_py_writer = Some "py_write_onnx"
                      && s.s_py_reader = Some "py_read_onnx" ->
       incr pass_count; Printf.printf "  ✓ ^onnx has correct R/Python helper names\n"
   | _ ->
       incr fail_count; Printf.printf "  ✗ ^onnx R/Python helper names incorrect\n") ;

  (* ONNX placeholder writer throws descriptive error *)
  let (v, _) = eval_string_env {| (^onnx).writer("test.onnx", 1) |} (Packages.init_env ()) in
  (match v with
   | VError { message; _ } when contains message "does not have a T-native implementation yet" ->
       incr pass_count; Printf.printf "  ✓ ^onnx placeholder writer throws descriptive error\n"
   | _ ->
       incr fail_count; Printf.printf "  ✗ ^onnx placeholder writer failed to throw error\n") ;

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
    incr fail_count; Printf.printf "  ✗ Custom serializer mock failed\n"
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
       incr fail_count; Printf.printf "  ✗ Static coherence check failed on matching formats. Got: %s\n" 
         (Ast.Utils.value_to_string other));

  (* 4b. Explicit dependency checks happen before pipeline emission/build *)
  let env_onnx = Packages.init_env () in
  let (v, _) = eval_string_env {|
    p = pipeline {
       model = node(command = <{ 1 }>, runtime = Python, serializer = ^onnx)
    }
    populate_pipeline(p)
  |} env_onnx in
  (match v with
   | VError { code; message; _ }
     when code = FileError
       && contains_all message
            ["tproject.toml"; "onnxruntime"; "skl2onnx"; "cannot add these dependencies automatically"] ->
       incr pass_count; Printf.printf "  ✓ Missing serializer dependencies fail statically without implicit injection\n"
   | other ->
       incr fail_count;
       Printf.printf "  ✗ Explicit dependency check failed for ONNX pipeline. Got: %s\n"
         (Ast.Utils.value_to_string other));

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
         incr fail_count; Printf.printf "  ✗ Pipeline Nix emission still injects serializer dependencies implicitly\n"
       end
   | other ->
       incr fail_count;
       Printf.printf "  ✗ Failed to build pipeline for Nix emission test. Got: %s\n"
         (Ast.Utils.value_to_string other));

  (* 5. Robustness: Placeholder error *)
  let (v, _) = eval_string_env {| (^csv).writer("test.csv", 1) |} (Packages.init_env ()) in
  (match v with
   | VError { message; _ } when contains message "does not have a T-native implementation yet" ->
       incr pass_count; Printf.printf "  ✓ Placeholder writer throws descriptive error\n"
   | _ ->
       incr fail_count; Printf.printf "  ✗ Placeholder writer failed to throw error\n") ;

  (* 6. Invalid Identifiers *)
  let (v, _) = eval_string_env {| ^non_existent |} (Packages.init_env ()) in
  (match v with
   | VSymbol "^non_existent" ->
       incr pass_count; Printf.printf "  ✓ Invalid identifier resolves to symbol\n"
   | _ ->
       incr fail_count; Printf.printf "  ✗ Invalid identifier failed\n") ;

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
            incr fail_count; Printf.printf "  ✗ Dict failed to store VString for sniperts\n")
   | _ -> 
       incr fail_count; Printf.printf "  ✗ Snippet rejection test setup failed\n");

  print_newline ()
