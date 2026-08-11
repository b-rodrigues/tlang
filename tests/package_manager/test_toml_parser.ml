(* tests/package_manager/test_toml_parser.ml *)
(* Hard-error validation for [dependencies] entry types *)

let run_tests pass_count fail_count _failures _eval_string _eval_string_env _test =
  let test_pm name check =
    if check () then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  ✗ %s\n" name
    end
  in

  Printf.printf "Toml Parser — valid dependencies:\n";

  test_pm "parse git+tag table dep via DESCRIPTION.toml" (fun () ->
    let toml = {|
      [package]
      name = "test-pkg"

      [dependencies]
      foo = { git = "https://github.com/a/b", tag = "v1.0.0" }
    |} in
    match Toml_parser.parse_description_toml toml with
    | Ok cfg -> cfg.dependencies = [{ Package_types.dep_name = "foo";
                                      git_url = "https://github.com/a/b";
                                      tag = "v1.0.0" }]
    | Error _ -> false);

  test_pm "parse git+tag table dep via tproject.toml" (fun () ->
    let toml = {|
      [project]
      name = "test-proj"

      [dependencies]
      bar = { git = "https://github.com/x/y", tag = "v2.0.0" }

      [t]
      min_version = "0.55.0"
    |} in
    match Toml_parser.parse_tproject_toml toml with
    | Ok cfg -> cfg.proj_dependencies = [{ Package_types.dep_name = "bar";
                                           git_url = "https://github.com/x/y";
                                           tag = "v2.0.0" }]
    | Error _ -> false);

  test_pm "empty [dependencies] section" (fun () ->
    let toml = {|
      [package]
      name = "test-pkg"

      [dependencies]
    |} in
    match Toml_parser.parse_description_toml toml with
    | Ok cfg -> cfg.dependencies = []
    | Error _ -> false);

  test_pm "no [dependencies] section" (fun () ->
    let toml = {|
      [package]
      name = "test-pkg"
    |} in
    match Toml_parser.parse_description_toml toml with
    | Ok cfg -> cfg.dependencies = []
    | Error _ -> false);

  print_newline ();

  Printf.printf "Toml Parser — hard errors on invalid [dependencies] entries:\n";

  test_pm "array value rejected (DESCRIPTION.toml)" (fun () ->
    let toml = {|
      [package]
      name = "test-pkg"

      [dependencies]
      python = ["polars", "pyarrow"]
    |} in
    match Toml_parser.parse_description_toml toml with
    | Ok _ -> false
    | Error msg -> Test_helpers.contains msg "python");

  test_pm "array value rejected with py-dependencies pointer (tproject.toml)" (fun () ->
    let toml = {|
      [project]
      name = "test-proj"

      [dependencies]
      python = ["polars", "pyarrow"]

      [t]
      min_version = "0.55.0"
    |} in
    match Toml_parser.parse_tproject_toml toml with
    | Ok _ -> false
    | Error msg -> Test_helpers.contains msg "python"
                   && Test_helpers.contains msg "[py-dependencies]");

  test_pm "version-constraint string rejected" (fun () ->
    let toml = {|
      [project]
      name = "test-proj"

      [dependencies]
      tlang = ">=0.52.0"

      [t]
      min_version = "0.55.0"
    |} in
    match Toml_parser.parse_tproject_toml toml with
    | Ok _ -> false
    | Error msg -> Test_helpers.contains msg "tlang"
                   && Test_helpers.contains msg "[t]");

  test_pm "star-named string rejected" (fun () ->
    let toml = {|
      [project]
      name = "test-proj"

      [dependencies]
      base = "*"

      [t]
      min_version = "0.55.0"
    |} in
    match Toml_parser.parse_tproject_toml toml with
    | Ok _ -> false
    | Error msg -> Test_helpers.contains msg "base");

  test_pm "table missing tag rejected" (fun () ->
    let toml = {|
      [project]
      name = "test-proj"

      [dependencies]
      foo = { git = "https://github.com/a/b" }

      [t]
      min_version = "0.55.0"
    |} in
    match Toml_parser.parse_tproject_toml toml with
    | Ok _ -> false
    | Error msg -> Test_helpers.contains msg "foo"
                   && Test_helpers.contains msg "git");

  test_pm "table missing git rejected" (fun () ->
    let toml = {|
      [project]
      name = "test-proj"

      [dependencies]
      foo = { tag = "v1.0.0" }

      [t]
      min_version = "0.55.0"
    |} in
    match Toml_parser.parse_tproject_toml toml with
    | Ok _ -> false
    | Error msg -> Test_helpers.contains msg "foo");

  test_pm "bool value rejected" (fun () ->
    let toml = {|
      [project]
      name = "test-proj"

      [dependencies]
      x = true

      [t]
      min_version = "0.55.0"
    |} in
    match Toml_parser.parse_tproject_toml toml with
    | Ok _ -> false
    | Error msg -> Test_helpers.contains msg "x");

  test_pm "DESCRIPTION.toml with string dep propagates error" (fun () ->
    let toml = {|
      [package]
      name = "test-pkg"

      [dependencies]
      dead = "not supported"
    |} in
    match Toml_parser.parse_description_toml toml with
    | Ok _ -> false
    | Error msg -> Test_helpers.contains msg "dead");

  print_newline ()
