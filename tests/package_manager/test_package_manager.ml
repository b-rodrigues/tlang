(* tests/package_manager/test_package_manager.ml *)
(* Tests for the package management scaffolding system *)

let run_tests pass_count fail_count _eval_string _eval_string_env _test =
  (* --- Helper for package_manager-specific tests --- *)
  let test_pm name check =
    if check () then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  ✗ %s\n" name
    end
  in

  (* ===================================================== *)
  Printf.printf "Package Manager — Name validation:\n";

  test_pm "valid lowercase name" (fun () ->
    Package_types.validate_name "my-package" = Ok "my-package");

  test_pm "valid with underscores" (fun () ->
    Package_types.validate_name "my_package" = Ok "my_package");

  test_pm "valid with digits" (fun () ->
    Package_types.validate_name "pkg2" = Ok "pkg2");

  test_pm "reject uppercase" (fun () ->
    match Package_types.validate_name "MyPackage" with Error _ -> true | Ok _ -> false);

  test_pm "reject starting with hyphen" (fun () ->
    match Package_types.validate_name "-bad" with Error _ -> true | Ok _ -> false);

  test_pm "reject empty" (fun () ->
    match Package_types.validate_name "" with Error _ -> true | Ok _ -> false);

  test_pm "reject special characters" (fun () ->
    match Package_types.validate_name "my@pkg" with Error _ -> true | Ok _ -> false);

  print_newline ();

  (* ===================================================== *)
  Printf.printf "Package Manager — Template engine:\n";

  test_pm "substitute single variable" (fun () ->
    Template_engine.substitute [("name", "foo")] "Hello {{name}}!" = "Hello foo!");

  test_pm "substitute multiple variables" (fun () ->
    Template_engine.substitute [("a", "1"); ("b", "2")] "{{a}}+{{b}}" = "1+2");

  test_pm "leave unknown variables" (fun () ->
    Template_engine.substitute [] "{{unknown}}" = "{{unknown}}");

  test_pm "handle empty template" (fun () ->
    Template_engine.substitute [("x", "y")] "" = "");

  test_pm "handle no variables in template" (fun () ->
    Template_engine.substitute [("x", "y")] "no vars here" = "no vars here");

  test_pm "handle spaces around variable name" (fun () ->
    Template_engine.substitute [("name", "T")] "{{ name }}" = "T");

  test_pm "handle unclosed braces" (fun () ->
    Template_engine.substitute [("x", "y")] "{{x" = "{{x");

  print_newline ();

  (* ===================================================== *)
  Printf.printf "Package Manager — TOML parsing:\n";

  let basic_toml = {|
[package]
name = "test-pkg"
version = "1.0.0"
description = "A test package"
authors = ["Alice <alice@example.com>"]
license = "MIT"

[dependencies]

[t]
min_version = "0.5.0"
|} in

  test_pm "parse valid DESCRIPTION.toml" (fun () ->
    match Toml_parser.parse_description_toml basic_toml with
    | Ok cfg -> cfg.name = "test-pkg" && cfg.version = "1.0.0"
                && cfg.license = "MIT" && cfg.min_t_version = "0.5.0"
    | Error _ -> false);

  test_pm "parse authors list" (fun () ->
    match Toml_parser.parse_description_toml basic_toml with
    | Ok cfg -> cfg.authors = ["Alice <alice@example.com>"]
    | Error _ -> false);

  test_pm "missing name gives error" (fun () ->
    let bad_toml = "[package]\nversion = \"1.0.0\"\n" in
    match Toml_parser.parse_description_toml bad_toml with
    | Error _ -> true | Ok _ -> false);

  test_pm "invalid TOML syntax gives error" (fun () ->
    match Toml_parser.parse_description_toml "this is not [toml\n" with
    | Error _ -> true | Ok _ -> false);

  let dep_toml = {|
[package]
name = "with-deps"
version = "0.2.0"

[dependencies]
stats = { git = "https://github.com/t-lang/stats", tag = "v0.5.0" }

[t]
min_version = "0.5.0"
|} in

  test_pm "parse dependencies" (fun () ->
    match Toml_parser.parse_description_toml dep_toml with
    | Ok cfg ->
      (match cfg.dependencies with
       | [dep] -> dep.dep_name = "stats"
                  && dep.git_url = "https://github.com/t-lang/stats"
                  && dep.tag = "v0.5.0"
       | _ -> false)
    | Error _ -> false);

  let project_toml = {|
[project]
name = "my-project"
description = "Test project"

[dependencies]

[t]
min_version = "0.5.0"
|} in

  test_pm "parse valid tproject.toml" (fun () ->
    match Toml_parser.parse_tproject_toml project_toml with
    | Ok cfg -> cfg.proj_name = "my-project"
                && cfg.proj_description = "Test project"
    | Error _ -> false);

  test_pm "serialize and re-parse package config" (fun () ->
    let cfg = Package_types.default_package_config "roundtrip" in
    let toml_str = Toml_parser.serialize_description_toml cfg in
    match Toml_parser.parse_description_toml toml_str with
    | Ok cfg2 -> cfg2.name = "roundtrip" && cfg2.version = "0.1.0"
    | Error _ -> false);

  print_newline ();

  (* ===================================================== *)
  Printf.printf "Package Manager — Scaffold (filesystem):\n";

  let temp_dir () =
    let d = Filename.get_temp_dir_name () ^ "/t-test-" ^
            string_of_int (int_of_float (Unix.gettimeofday () *. 1000.0) mod 100000) in
    d
  in

  test_pm "scaffold_package creates directory tree" (fun () ->
    let dir = temp_dir () in
    let opts = { (Package_types.default_options dir) with
                 target_name = Filename.basename dir;
                 no_git = true } in
    (* scaffold_package creates in CWD so we need to cd *)
    let old_cwd = Sys.getcwd () in
    Sys.chdir (Filename.dirname dir);
    let result = Scaffold.scaffold_package opts in
    Sys.chdir old_cwd;
    let ok = match result with
      | Ok () ->
        Sys.file_exists dir
        && Sys.file_exists (Filename.concat dir "DESCRIPTION.toml")
        && Sys.file_exists (Filename.concat dir "flake.nix")
        && Sys.file_exists (Filename.concat dir "README.md")
        && Sys.file_exists (Filename.concat dir "src/main.t")
        && Sys.is_directory (Filename.concat dir "tests")
        && Sys.is_directory (Filename.concat dir "examples")
        && Sys.is_directory (Filename.concat dir "docs")
      | Error _ -> false
    in
    (* Cleanup *)
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
    ok);

  test_pm "scaffold_project creates directory tree" (fun () ->
    let dir = temp_dir () in
    let opts = { (Package_types.default_options dir) with
                 target_name = Filename.basename dir;
                 no_git = true } in
    let old_cwd = Sys.getcwd () in
    Sys.chdir (Filename.dirname dir);
    let result = Scaffold.scaffold_project opts in
    Sys.chdir old_cwd;
    let ok = match result with
      | Ok () ->
        Sys.file_exists dir
        && Sys.file_exists (Filename.concat dir "tproject.toml")
        && Sys.file_exists (Filename.concat dir "flake.nix")
        && Sys.file_exists (Filename.concat dir "src/analysis.t")
        && Sys.is_directory (Filename.concat dir "data")
        && Sys.is_directory (Filename.concat dir "outputs")
        && Sys.is_directory (Filename.concat dir "tests")
      | Error _ -> false
    in
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
    ok);

  test_pm "scaffold rejects invalid name" (fun () ->
    let opts = { (Package_types.default_options "Bad-Name") with no_git = true } in
    match Scaffold.scaffold_package opts with
    | Error _ -> true | Ok () -> false);

  test_pm "scaffold rejects existing dir without --force" (fun () ->
    let dir = Filename.get_temp_dir_name () ^ "/t-exist-test" in
    Unix.mkdir dir 0o755;
    let opts = { (Package_types.default_options (Filename.basename dir)) with
                 no_git = true; force = false } in
    let old_cwd = Sys.getcwd () in
    Sys.chdir (Filename.dirname dir);
    let result = Scaffold.scaffold_package opts in
    Sys.chdir old_cwd;
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
    match result with Error _ -> true | Ok () -> false);

  test_pm "scaffold with --force overwrites existing dir" (fun () ->
    let dir = Filename.get_temp_dir_name () ^ "/t-force-test" in
    Unix.mkdir dir 0o755;
    let opts = { (Package_types.default_options (Filename.basename dir)) with
                 no_git = true; force = true } in
    let old_cwd = Sys.getcwd () in
    Sys.chdir (Filename.dirname dir);
    let result = Scaffold.scaffold_package opts in
    Sys.chdir old_cwd;
    let ok = match result with Ok () -> true | Error _ -> false in
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
    ok);

  print_newline ();

  (* ===================================================== *)
  Printf.printf "Package Manager — CLI flag parsing:\n";

  test_pm "parse basic name" (fun () ->
    match Scaffold.parse_init_flags ["my-pkg"] with
    | Ok opts -> opts.target_name = "my-pkg"
    | Error _ -> false);

  test_pm "parse --author flag" (fun () ->
    match Scaffold.parse_init_flags ["my-pkg"; "--author"; "Jane Doe"] with
    | Ok opts -> opts.author = "Jane Doe"
    | Error _ -> false);

  test_pm "parse --license flag" (fun () ->
    match Scaffold.parse_init_flags ["my-pkg"; "--license"; "MIT"] with
    | Ok opts -> opts.license = "MIT"
    | Error _ -> false);

  test_pm "parse --no-git flag" (fun () ->
    match Scaffold.parse_init_flags ["my-pkg"; "--no-git"] with
    | Ok opts -> opts.no_git = true
    | Error _ -> false);

  test_pm "parse --force flag" (fun () ->
    match Scaffold.parse_init_flags ["my-pkg"; "--force"] with
    | Ok opts -> opts.force = true
    | Error _ -> false);

  test_pm "parse combined flags" (fun () ->
    match Scaffold.parse_init_flags ["my-pkg"; "--no-git"; "--force"; "--license"; "MIT"] with
    | Ok opts -> opts.no_git && opts.force && opts.license = "MIT"
    | Error _ -> false);

  test_pm "missing name gives error" (fun () ->
    match Scaffold.parse_init_flags [] with
    | Error _ -> true | Ok _ -> false);

  print_newline ();

  (* ===================================================== *)
  Printf.printf "Package Manager — Nix generator:\n";

  let make_dep name url tag =
    Package_types.{ dep_name = name; git_url = url; tag } in

  test_pm "github URL to flake input" (fun () ->
    match Nix_generator.git_url_to_flake_input
      (make_dep "stats" "https://github.com/t-lang/stats" "v0.5.0") with
    | Ok s -> s = "github:t-lang/stats/v0.5.0"
    | Error _ -> false);

  test_pm "gitlab URL to flake input" (fun () ->
    match Nix_generator.git_url_to_flake_input
      (make_dep "x" "https://gitlab.com/user/repo" "v1.0") with
    | Ok s -> s = "gitlab:user/repo/v1.0"
    | Error _ -> false);

  test_pm "strip .git suffix from URL" (fun () ->
    match Nix_generator.git_url_to_flake_input
      (make_dep "x" "https://github.com/user/repo.git" "v1.0") with
    | Ok s -> s = "github:user/repo/v1.0"
    | Error _ -> false);

  test_pm "generic git URL uses git+ prefix" (fun () ->
    match Nix_generator.git_url_to_flake_input
      (make_dep "x" "https://example.com/repo" "v1.0") with
    | Ok s -> s = "git+https://example.com/repo?ref=v1.0"
    | Error _ -> false);

  test_pm "generate project flake with deps" (fun () ->
    let flake = Nix_generator.generate_project_flake
      ~project_name:"test-proj" ~nixpkgs_date:"2026-02-10"
      ~t_version:"0.5.0"
      ~deps:[make_dep "stats" "https://github.com/t-lang/stats" "v0.5.0"] in
    (* Check key parts are present *)
    let has s = try ignore (Str.search_forward (Str.regexp_string s) flake 0); true
                with Not_found -> false in
    has "stats.url = \"github:t-lang/stats/v0.5.0\";"
    && has "tPackages"
    && has "stats.packages"
    && has "t-lang.url"
    && has "rstats-on-nix.cachix.org");

  test_pm "generate project flake no deps" (fun () ->
    let flake = Nix_generator.generate_project_flake
      ~project_name:"empty" ~nixpkgs_date:"2026-02-10"
      ~t_version:"0.5.0" ~deps:[] in
    let has s = try ignore (Str.search_forward (Str.regexp_string s) flake 0); true
                with Not_found -> false in
    has "t-lang.url" && not (has "tPackages"));

  test_pm "generate package flake" (fun () ->
    let flake = Nix_generator.generate_package_flake
      ~package_name:"my-pkg" ~package_version:"0.2.0"
      ~nixpkgs_date:"2026-02-10" ~t_version:"0.5.0" ~deps:[] in
    let has s = try ignore (Str.search_forward (Str.regexp_string s) flake 0); true
                with Not_found -> false in
    has "packages.default" && has "pname = \"t-my-pkg\""
    && has "my-pkg" && has "version = \"0.2.0\"");

  print_newline ()
