(* tests/package_manager/test_package_manager.ml *)
(* Tests for the package management scaffolding system *)

let run_tests pass_count fail_count _eval_string eval_string_env _test =
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

[r-dependencies]
packages = ["dplyr", "tidyr"]

[py-dependencies]
version = "python310"
packages = ["pandas"]

[t]
min_version = "0.5.0"
|} in

  test_pm "parse valid tproject.toml" (fun () ->
    match Toml_parser.parse_tproject_toml project_toml with
    | Ok cfg -> cfg.proj_name = "my-project"
                && cfg.proj_description = "Test project"
                && cfg.proj_r_dependencies = ["dplyr"; "tidyr"]
                && cfg.proj_py_version = "python310"
                && cfg.proj_py_dependencies = ["pandas"]
    | Error _ -> false);

  test_pm "serialize and re-parse package config" (fun () ->
    let cfg = Package_types.default_package_config "roundtrip" in
    let toml_str = Toml_parser.serialize_description_toml cfg in
    match Toml_parser.parse_description_toml toml_str with
    | Ok cfg2 -> cfg2.name = "roundtrip" && cfg2.version = "0.1.0"
    | Error _ -> false);

  test_pm "serialize and re-parse project config" (fun () ->
    let cfg0 = Package_types.default_project_config "roundtrip-proj" in
    let cfg = { cfg0 with proj_r_dependencies = ["foo"]; proj_py_dependencies = ["bar"] } in
    let toml_str = Toml_parser.serialize_tproject_toml cfg in
    match Toml_parser.parse_tproject_toml toml_str with
    | Ok cfg2 -> cfg2.proj_name = "roundtrip-proj" 
                 && cfg2.proj_r_dependencies = ["foo"]
                 && cfg2.proj_py_dependencies = ["bar"]
    | Error _ -> false);

  print_newline ();

  (* ===================================================== *)
  Printf.printf "Package Manager — Update manager:\n";

  Random.self_init ();

  let rec make_temp_dir attempts =
    if attempts <= 0 then
      None
    else
      let candidate =
        Filename.concat
          (Filename.get_temp_dir_name ())
          (Printf.sprintf "t-update-check-%d-%06d"
             (Unix.getpid ())
             (Random.int 1_000_000))
      in
      try
        Unix.mkdir candidate 0o755;
        Some candidate
      with Unix.Unix_error (Unix.EEXIST, _, _) ->
        make_temp_dir (attempts - 1)
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

  let create_test_package base_dir package_name source =
    let pkg_dir = Filename.concat base_dir package_name in
    let src_dir = Filename.concat pkg_dir "src" in
    Unix.mkdir pkg_dir 0o755;
    Unix.mkdir src_dir 0o755;
    let ch = open_out (Filename.concat src_dir "main.t") in
    output_string ch source;
    close_out ch
  in

  let unreachable_package_path =
    Filename.concat (Filename.get_temp_dir_name ()) "__tlang_no_packages__"
  in

  let with_package_path path f =
    let original =
      try Some (Sys.getenv "T_PACKAGE_PATH") with Not_found -> None
    in
    Unix.putenv "T_PACKAGE_PATH" path;
    let restore () =
      match original with
      | Some value -> Unix.putenv "T_PACKAGE_PATH" value
      | None ->
          (* OCaml's standard library does not provide a portable unsetenv here,
             so restore to an unreachable sentinel path instead of leaving the
             temporary package directory discoverable to later tests. This
             differs from true unsetting because T_PACKAGE_PATH still exists in
             the None case, but only with a value that cannot resolve packages. *)
          Unix.putenv "T_PACKAGE_PATH" unreachable_package_path
    in
    try
      let result = f () in
      restore ();
      result
    with exn ->
      restore ();
      raise exn
  in

  test_pm "parse remote tag refs ignores dereferenced tags" (fun () ->
    let output = String.concat "\n"
      [ "abc123\trefs/tags/v0.1.0"
      ; "abc123\trefs/tags/v0.1.0^{}"
      ; "def456\trefs/tags/v0.2.0"
      ; "fedcba\trefs/heads/main"
      ]
    in
    Update_manager.parse_remote_tag_refs output = ["v0.1.0"; "v0.2.0"]);

  let git_command_succeeds argv =
    let pid = Unix.create_process "git" argv Unix.stdin Unix.stdout Unix.stderr in
    match Unix.waitpid [] pid with
    | _, Unix.WEXITED 0 -> true
    | _, _ -> false
  in

  let write_file path content =
    let ch = open_out path in
    output_string ch content;
    close_out ch
  in

  (* Helper: restore CI env var to its saved value. Setting to "" is
     equivalent to "unset" for validate_update_prerequisites because
     its check requires a non-empty, non-whitespace value. *)
  let restore_ci saved =
    match saved with Some v -> Unix.putenv "CI" v | None -> Unix.putenv "CI" ""
  in

  test_pm "check_remote_tags finds newer local git tag" (fun () ->
    match make_temp_dir 8 with
    | None -> false
    | Some base_dir ->
        let repo_dir = Filename.concat base_dir "remote-repo" in
        let project_dir = Filename.concat base_dir "project" in
        let result =
          try
            let setup_ok =
              (try Unix.mkdir repo_dir 0o755; true with Unix.Unix_error _ -> false)
              && git_command_succeeds [| "git"; "-C"; repo_dir; "init"; "--quiet" |]
              && git_command_succeeds [| "git"; "-C"; repo_dir; "config"; "user.email"; "test@example.com" |]
              && git_command_succeeds [| "git"; "-C"; repo_dir; "config"; "user.name"; "Test User" |]
            in
            if not setup_ok then
              Error "setup failed"
            else begin
              write_file (Filename.concat repo_dir "README.md") "test repo\n";
              let committed =
                git_command_succeeds [| "git"; "-C"; repo_dir; "add"; "README.md" |]
                && git_command_succeeds [| "git"; "-C"; repo_dir; "commit"; "--quiet"; "-m"; "init" |]
                && git_command_succeeds [| "git"; "-C"; repo_dir; "tag"; "v0.1.0" |]
                && git_command_succeeds [| "git"; "-C"; repo_dir; "tag"; "v0.2.0" |]
                && (try Unix.mkdir project_dir 0o755; true with Unix.Unix_error _ -> false)
              in
              if not committed then
                Error "repo commit failed"
              else begin
                write_file
                  (Filename.concat project_dir "tproject.toml")
                  (Printf.sprintf
                     {|[project]
name = "my-project"
description = "Test project"

[dependencies]
stats = { git = "%s", tag = "v0.1.0" }

[t]
min_version = "0.5.0"
|}
                     repo_dir);
                let old_cwd = Sys.getcwd () in
                Sys.chdir project_dir;
                let check_result =
                  try Update_manager.check_remote_tags () with exn ->
                    Sys.chdir old_cwd;
                    raise exn
                in
                Sys.chdir old_cwd;
                check_result
              end
            end
          with exn ->
            Error (Printexc.to_string exn)
        in
        let cleanup_ok =
          try
            remove_path base_dir;
            true
          with _ -> false
        in
        match result with
        | Ok [update] ->
            cleanup_ok
            && update.dependency_name = "stats"
            && update.current_tag = "v0.1.0"
            && update.latest_tag = "v0.2.0"
        | _ -> false);

  test_pm "validate_update_prerequisites requires a git remote" (fun () ->
    match make_temp_dir 8 with
    | None -> false
    | Some base_dir ->
        let repo_dir = Filename.concat base_dir "project" in
        let saved_ci = Sys.getenv_opt "CI" in
        let result =
          try
            let setup_ok =
              (try Unix.mkdir repo_dir 0o755; true with Unix.Unix_error _ -> false)
              && git_command_succeeds [| "git"; "-C"; repo_dir; "init"; "--quiet" |]
              && git_command_succeeds [| "git"; "-C"; repo_dir; "config"; "user.email"; "test@example.com" |]
              && git_command_succeeds [| "git"; "-C"; repo_dir; "config"; "user.name"; "Test User" |]
            in
            if not setup_ok then
              Error "setup failed"
            else
              let old_cwd = Sys.getcwd () in
              Sys.chdir repo_dir;
              Unix.putenv "CI" "";
              let validation_result =
                try Update_manager.validate_update_prerequisites () with exn ->
                  restore_ci saved_ci;
                  Sys.chdir old_cwd;
                  raise exn
              in
              restore_ci saved_ci;
              Sys.chdir old_cwd;
              validation_result
          with exn ->
            restore_ci saved_ci;
            Error (Printexc.to_string exn)
        in
        let cleanup_ok =
          try
            remove_path base_dir;
            true
          with _ -> false
        in
        cleanup_ok
        &&
        (match result with
        | Error msg ->
            msg = "Git remote is not configured. Add a remote and push the project before running `t update`."
        | Ok () -> false));

  test_pm "validate_update_prerequisites requires a clean working tree" (fun () ->
    match make_temp_dir 8 with
    | None -> false
    | Some base_dir ->
        let remote_dir = Filename.concat base_dir "remote.git" in
        let repo_dir = Filename.concat base_dir "project" in
        let saved_ci = Sys.getenv_opt "CI" in
        let result =
          try
            let setup_ok =
              git_command_succeeds [| "git"; "init"; "--bare"; remote_dir |]
              && (try Unix.mkdir repo_dir 0o755; true with Unix.Unix_error _ -> false)
              && git_command_succeeds [| "git"; "-C"; repo_dir; "init"; "--quiet" |]
              && git_command_succeeds [| "git"; "-C"; repo_dir; "config"; "user.email"; "test@example.com" |]
              && git_command_succeeds [| "git"; "-C"; repo_dir; "config"; "user.name"; "Test User" |]
            in
            if not setup_ok then
              Error "setup failed"
            else begin
              write_file (Filename.concat repo_dir "README.md") "clean repo\n";
              let remote_ok =
                git_command_succeeds [| "git"; "-C"; repo_dir; "add"; "README.md" |]
                && git_command_succeeds [| "git"; "-C"; repo_dir; "commit"; "--quiet"; "-m"; "init" |]
                && git_command_succeeds [| "git"; "-C"; repo_dir; "remote"; "add"; "origin"; remote_dir |]
              in
              if not remote_ok then
                Error "remote setup failed"
              else begin
                write_file (Filename.concat repo_dir "dirty.txt") "needs commit\n";
                let old_cwd = Sys.getcwd () in
                Sys.chdir repo_dir;
                Unix.putenv "CI" "";
                let validation_result =
                  try Update_manager.validate_update_prerequisites () with exn ->
                    restore_ci saved_ci;
                    Sys.chdir old_cwd;
                    raise exn
                in
                restore_ci saved_ci;
                Sys.chdir old_cwd;
                validation_result
              end
            end
          with exn ->
            restore_ci saved_ci;
            Error (Printexc.to_string exn)
        in
        let cleanup_ok =
          try
            remove_path base_dir;
            true
          with _ -> false
        in
        cleanup_ok
        &&
        (match result with
        | Error msg -> msg = "Git working directory is not clean. Commit or stash changes first."
        | Ok () -> false));

  test_pm "validate_update_prerequisites accepts clean repo with remote" (fun () ->
    match make_temp_dir 8 with
    | None -> false
    | Some base_dir ->
        let remote_dir = Filename.concat base_dir "remote.git" in
        let repo_dir = Filename.concat base_dir "project" in
        let result =
          try
            let setup_ok =
              git_command_succeeds [| "git"; "init"; "--bare"; remote_dir |]
              && (try Unix.mkdir repo_dir 0o755; true with Unix.Unix_error _ -> false)
              && git_command_succeeds [| "git"; "-C"; repo_dir; "init"; "--quiet" |]
              && git_command_succeeds [| "git"; "-C"; repo_dir; "config"; "user.email"; "test@example.com" |]
              && git_command_succeeds [| "git"; "-C"; repo_dir; "config"; "user.name"; "Test User" |]
            in
            if not setup_ok then
              Error "setup failed"
            else begin
              write_file (Filename.concat repo_dir "README.md") "clean repo\n";
              let remote_ok =
                git_command_succeeds [| "git"; "-C"; repo_dir; "add"; "README.md" |]
                && git_command_succeeds [| "git"; "-C"; repo_dir; "commit"; "--quiet"; "-m"; "init" |]
                && git_command_succeeds [| "git"; "-C"; repo_dir; "remote"; "add"; "origin"; remote_dir |]
              in
              if not remote_ok then
                Error "remote setup failed"
              else begin
                let old_cwd = Sys.getcwd () in
                Sys.chdir repo_dir;
                let validation_result =
                  try Update_manager.validate_update_prerequisites () with exn ->
                    Sys.chdir old_cwd;
                    raise exn
                in
                Sys.chdir old_cwd;
                validation_result
              end
            end
          with exn ->
            Error (Printexc.to_string exn)
        in
        let cleanup_ok =
          try
            remove_path base_dir;
            true
          with _ -> false
        in
        cleanup_ok && result = Ok ());

  test_pm "validate_update_prerequisites skips checks when CI is set" (fun () ->
    match make_temp_dir 8 with
    | None -> false
    | Some base_dir ->
        let repo_dir = Filename.concat base_dir "project" in
        let saved_ci = Sys.getenv_opt "CI" in
        let result =
          try
            let setup_ok =
              (try Unix.mkdir repo_dir 0o755; true with Unix.Unix_error _ -> false)
              && git_command_succeeds [| "git"; "-C"; repo_dir; "init"; "--quiet" |]
              && git_command_succeeds [| "git"; "-C"; repo_dir; "config"; "user.email"; "test@example.com" |]
              && git_command_succeeds [| "git"; "-C"; repo_dir; "config"; "user.name"; "Test User" |]
            in
            if not setup_ok then
              Error "setup failed"
            else
              let old_cwd = Sys.getcwd () in
              Sys.chdir repo_dir;
              Unix.putenv "CI" "true";
              let validation_result =
                try Update_manager.validate_update_prerequisites () with exn ->
                  restore_ci saved_ci;
                  Sys.chdir old_cwd;
                  raise exn
              in
              restore_ci saved_ci;
              Sys.chdir old_cwd;
              validation_result
          with exn ->
            restore_ci saved_ci;
            Error (Printexc.to_string exn)
        in
        let cleanup_ok =
          try
            remove_path base_dir;
            true
          with _ -> false
        in
        cleanup_ok && result = Ok ());

  test_pm "update_flake_lock reports missing project config before git checks" (fun () ->
    match make_temp_dir 8 with
    | None -> false
    | Some base_dir ->
        let result =
          try
            let old_cwd = Sys.getcwd () in
            Sys.chdir base_dir;
            let update_result =
              try Update_manager.update_flake_lock () with exn ->
                Sys.chdir old_cwd;
                raise exn
            in
            Sys.chdir old_cwd;
            update_result
          with exn ->
            Error (Printexc.to_string exn)
        in
        let cleanup_ok =
          try
            remove_path base_dir;
            true
          with _ -> false
        in
        cleanup_ok
        &&
        (match result with
        | Error msg -> msg = "No tproject.toml or DESCRIPTION.toml found in the current directory."
        | Ok () -> false));

  test_pm "summarize_flake_lock_changes reports structured updates" (fun () ->
    let before = {|
{
  "nodes": {
    "nixpkgs": {
      "locked": {
        "lastModified": 1,
        "narHash": "sha256-old",
        "rev": "oldrev"
      },
      "original": {
        "ref": "2026-03-11"
      }
    }
  }
}
|} in
    let after = {|
{
  "nodes": {
    "nixpkgs": {
      "locked": {
        "lastModified": 2,
        "narHash": "sha256-new",
        "rev": "newrev"
      },
      "original": {
        "ref": "2026-03-12"
      }
    }
  }
}
|} in
    let summary = Update_manager.summarize_flake_lock_changes (Some before) (Some after) in
    List.mem "  - nixpkgs" summary
    && List.mem "      original.ref: 2026-03-11 -> 2026-03-12" summary
    && List.mem "      locked.lastModified: 1 -> 2" summary
    && List.mem "      locked.narHash: sha256-old -> sha256-new" summary
    && List.mem "      locked.rev: oldrev -> newrev" summary);

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
        && Sys.file_exists (Filename.concat dir "src/pipeline.t")
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
      ~deps:[make_dep "stats" "https://github.com/t-lang/stats" "v0.5.0"] () in
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
      ~t_version:"0.5.0" ~deps:[] () in
    let has s = try ignore (Str.search_forward (Str.regexp_string s) flake 0); true
                with Not_found -> false in
    has "t-lang.url" && not (has "tPackages"));

  test_pm "generate package flake" (fun () ->
    let flake = Nix_generator.generate_package_flake
      ~package_name:"my-pkg" ~package_version:"0.2.0"
      ~nixpkgs_date:"2026-02-10" ~t_version:"0.5.0" ~deps:[] () in
    let has s = try ignore (Str.search_forward (Str.regexp_string s) flake 0); true
                with Not_found -> false in
    has "packages.default" && has "pname = \"t-my-pkg\""
    && has "my-pkg" && has "version = \"0.2.0\"");

  test_pm "generate project flake with additional_tools" (fun () ->
    let flake = Nix_generator.generate_project_flake
      ~project_name:"test-proj" ~nixpkgs_date:"2026-02-10"
      ~t_version:"0.5.0" ~deps:[]
      ~additional_tools:["pandoc"; "jq"] () in
    let has s = try ignore (Str.search_forward (Str.regexp_string s) flake 0); true
                with Not_found -> false in
    has "additionalTools" && has "pandoc" && has "jq"
    && has "++ additionalTools");

  test_pm "generate project flake auto-provisions quarto extension" (fun () ->
    let flake = Nix_generator.generate_project_flake
      ~project_name:"test-proj" ~nixpkgs_date:"2026-02-10"
      ~t_version:"0.5.0" ~deps:[]
      ~additional_tools:["quarto"; "jq"] () in
    let has s = try ignore (Str.search_forward (Str.regexp_string s) flake 0); true
                with Not_found -> false in
    has "mkdir -p _extensions"
    && has "_extensions/tlang"
    && has "quarto_ext_stamp=\"$quarto_ext_path/.tlang-store-path\""
    && has "cp -R \"$expected_quarto_ext\"/. \"$quarto_ext_path\"/"
    && has "Provisioned T Quarto extension"
    && has "Quarto is enabled via [additional-tools]"
    && not (has "ln -s \"$expected_quarto_ext\" \"_extensions/tlang\"");

  test_pm "generate project flake with latex_pkgs" (fun () ->
    let flake = Nix_generator.generate_project_flake
      ~project_name:"test-proj" ~nixpkgs_date:"2026-02-10"
      ~t_version:"0.5.0" ~deps:[]
      ~latex_pkgs:["amsmath"; "hyperref"] () in
    let has s = try ignore (Str.search_forward (Str.regexp_string s) flake 0); true
                with Not_found -> false in
    has "latex-env" && has "texlive.combine"
    && has "scheme-small" && has "amsmath" && has "hyperref");

  test_pm "generate package flake with additional_tools and latex_pkgs" (fun () ->
    let flake = Nix_generator.generate_package_flake
      ~package_name:"my-pkg" ~package_version:"0.2.0"
      ~nixpkgs_date:"2026-02-10" ~t_version:"0.5.0" ~deps:[]
      ~additional_tools:["pandoc"] ~latex_pkgs:["amsmath"] () in
    let has s = try ignore (Str.search_forward (Str.regexp_string s) flake 0); true
                with Not_found -> false in
    (* The definitions "additionalTools = ..." and "latex-env = ..." only appear
       in the let...in block; references in buildInputs lack the " = " suffix *)
    has "additionalTools = " && has "latex-env = " && has "texlive.combine"
    && has "amsmath" && has "pandoc"
    (* buildInputs should reference latex-env and ++ additionalTools *)
    && has "latex-env\n" && has "++ additionalTools");

  test_pm "invalid nix identifiers are rejected from additional_tools" (fun () ->
    let flake = Nix_generator.generate_project_flake
      ~project_name:"test-proj" ~nixpkgs_date:"2026-02-10"
      ~t_version:"0.5.0" ~deps:[]
      ~warn_invalid_pkg_names:false
      ~additional_tools:["valid-pkg"; "$(evil)"; "valid_pkg2"; "bad pkg"] () in
    let has s = try ignore (Str.search_forward (Str.regexp_string s) flake 0); true
                with Not_found -> false in
    has "valid-pkg" && has "valid_pkg2"
    && not (has "$(evil)") && not (has "bad pkg"));

  print_newline ();

  (* ===================================================== *)
  Printf.printf "Package Manager — Package import conflicts:\n";

  test_pm "importing a standard package is a no-op success" (fun () ->
    let env = Packages.init_env () in
    let (before_mean, _) = eval_string_env "type(mean)" env in
    let (import_result, env_after_import) = eval_string_env "import stats" env in
    let (after_mean, _) = eval_string_env "type(mean)" env_after_import in
    Ast.Utils.value_to_string before_mean = {|"BuiltinFunction"|}
    && Ast.Utils.value_to_string import_result = "null"
    && Ast.Utils.value_to_string after_mean = {|"BuiltinFunction"|});

  test_pm "full import keeps builtin name and prefixes conflicting package binding" (fun () ->
    match make_temp_dir 8 with
    | None -> false
    | Some base_dir ->
        create_test_package base_dir "alpha" "mean = 999\nalpha_only = 1\n";
        let success =
          with_package_path base_dir (fun () ->
            let env = Packages.init_env () in
            let (_v, env_after_import) = eval_string_env "import alpha" env in
            let (builtin_mean, _) = eval_string_env "type(mean)" env_after_import in
            let (prefixed_mean, _) = eval_string_env "alpha_mean" env_after_import in
            let (alpha_only, _) = eval_string_env "alpha_only" env_after_import in
            Ast.Utils.value_to_string builtin_mean = {|"BuiltinFunction"|}
            && Ast.Utils.value_to_string prefixed_mean = "999"
            && Ast.Utils.value_to_string alpha_only = "1")
        in
        remove_path base_dir;
        success);

  test_pm "full import renames both conflicting user package bindings" (fun () ->
    match make_temp_dir 8 with
    | None -> false
    | Some base_dir ->
        create_test_package base_dir "alpha" "shared = 10\nalpha_only = 1\n";
        create_test_package base_dir "beta" "shared = 20\nbeta_only = 2\n";
        let success =
          with_package_path base_dir (fun () ->
            let env = Packages.init_env () in
            let (_v1, env1) = eval_string_env "import alpha" env in
            let (_v2, env2) = eval_string_env "import beta" env1 in
            let (alpha_shared, _) = eval_string_env "alpha_shared" env2 in
            let (beta_shared, _) = eval_string_env "beta_shared" env2 in
            let (shared, _) = eval_string_env "shared" env2 in
            let (alpha_only, _) = eval_string_env "alpha_only" env2 in
            let (beta_only, _) = eval_string_env "beta_only" env2 in
            let shared_str = Ast.Utils.value_to_string shared in
            Ast.Utils.value_to_string alpha_shared = "10"
            && Ast.Utils.value_to_string beta_shared = "20"
            && String.length shared_str >= 5
            && String.sub shared_str 0 5 = "Error"
            && Ast.Utils.value_to_string alpha_only = "1"
            && Ast.Utils.value_to_string beta_only = "2")
        in
        remove_path base_dir;
        success);

  test_pm "selective import also prefixes conflicting package binding" (fun () ->
    match make_temp_dir 8 with
    | None -> false
    | Some base_dir ->
        create_test_package base_dir "gamma" "mean = 321\n";
        let success =
          with_package_path base_dir (fun () ->
            let env = Packages.init_env () in
            let (_v, env_after_import) = eval_string_env "import gamma[mean]" env in
            let (builtin_mean, _) = eval_string_env "type(mean)" env_after_import in
            let (prefixed_mean, _) = eval_string_env "gamma_mean" env_after_import in
            Ast.Utils.value_to_string builtin_mean = {|"BuiltinFunction"|}
            && Ast.Utils.value_to_string prefixed_mean = "321")
        in
        remove_path base_dir;
        success);

  print_newline ();

  (* ===================================================== *)
  Printf.printf "Package Manager — Test Discovery:\n";

  test_pm "discover_tests matches pattern" (fun () ->
    let dir = Filename.get_temp_dir_name () ^ "/t-test-disc" in
    ignore (Sys.command (Printf.sprintf "mkdir -p %s/tests" (Filename.quote dir)));
    let create f = 
      let ch = open_out (Filename.concat dir ("tests/" ^ f)) in
      close_out ch in
    create "test-foo.t";
    create "bar_test.t";
    create "ignored.t";
    create "test-nested.txt";
    let found = Test_discovery.discover_tests (Filename.concat dir "tests") in
    let base_names = List.map Filename.basename found in
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
    List.mem "test-foo.t" base_names && List.mem "bar_test.t" base_names &&
    not (List.mem "ignored.t" base_names));

  print_newline ();

  (* ===================================================== *)
  Printf.printf "Package Manager — Package Doctor:\n";

  test_pm "validate_package_structure checks files" (fun () ->
    let dir = Filename.get_temp_dir_name () ^ "/t-doctor-pkg" in
    ignore (Sys.command (Printf.sprintf "mkdir -p %s/src %s/tests" (Filename.quote dir) (Filename.quote dir)));
    let create f = 
      let ch = open_out (Filename.concat dir f) in
      close_out ch in
    create "DESCRIPTION.toml";
    create "flake.nix";
    create "README.md";
    create "LICENSE";
    create "src/main.t";
    create "tests/test.t";
    let issues = Package_doctor.validate_package_structure dir in
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
    issues = []); (* Should be empty if valid *)

  test_pm "validate_package_structure detects missing config" (fun () ->
    let dir = Filename.get_temp_dir_name () ^ "/t-doctor-bad" in
    ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)));
    let issues = Package_doctor.validate_package_structure dir in
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
    List.exists (fun i -> let open Package_doctor in i.level = Error && 
                          String.contains i.message 'D' (* DESCRIPTION *)) issues);


  print_newline ();

  (* ===================================================== *)
  Printf.printf "Package Manager — Release Manager:\n";

  test_pm "get_package_version parses version" (fun () ->
    let dir = Filename.get_temp_dir_name () ^ "/t-release-ver" in
    ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)));
    let ch = open_out (Filename.concat dir "DESCRIPTION.toml") in
    output_string ch "[package]\nname = \"foo\"\nversion = \"1.2.3\"\ndescription=\"d\"\nauthors=[]\nlicense=\"MIT\"";
    close_out ch;
    let ver = Release_manager.get_package_version dir in
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
    ver = Ok "1.2.3");

  test_pm "validate_changelog finds version entry" (fun () ->
    let dir = Filename.get_temp_dir_name () ^ "/t-release-log" in
    ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)));
    let ch = open_out (Filename.concat dir "CHANGELOG.md") in
    output_string ch "# Changelog\n\n## [1.2.3] - 2023-01-01\n\n- Initial release\n";
    close_out ch;
    let res = Release_manager.validate_changelog dir "1.2.3" in
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
    res = Ok ());

  test_pm "validate_changelog fails on missing entry" (fun () ->
    let dir = Filename.get_temp_dir_name () ^ "/t-release-nolog" in
    ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)));
    let ch = open_out (Filename.concat dir "CHANGELOG.md") in
    output_string ch "# Changelog\n\n## [0.1.0]\n";
    close_out ch;
    let res = Release_manager.validate_changelog dir "1.2.3" in
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
    match res with Error _ -> true | Ok _ -> false);

  print_newline ();

  (* ===================================================== *)
  Printf.printf "Package Manager — Documentation Manager:\n";

  test_pm "validate_docs accepts valid structure" (fun () ->
    let dir = Filename.get_temp_dir_name () ^ "/t-docs-valid" in
    ignore (Sys.command (Printf.sprintf "mkdir -p %s/docs" (Filename.quote dir)));
    ignore (Sys.command (Printf.sprintf "touch %s/docs/index.md" (Filename.quote dir)));
    let res = Documentation_manager.validate_docs dir in
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
    res = Ok ());

  test_pm "validate_docs rejects missing docs dir" (fun () ->
    let dir = Filename.get_temp_dir_name () ^ "/t-docs-missing" in
    ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)));
    let res = Documentation_manager.validate_docs dir in
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
    match res with Error _ -> true | Ok _ -> false);

  test_pm "validate_docs rejects missing index.md" (fun () ->
    let dir = Filename.get_temp_dir_name () ^ "/t-docs-noindex" in
    ignore (Sys.command (Printf.sprintf "mkdir -p %s/docs" (Filename.quote dir)));
    let res = Documentation_manager.validate_docs dir in
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
    match res with Error _ -> true | Ok _ -> false);

  print_newline ()
