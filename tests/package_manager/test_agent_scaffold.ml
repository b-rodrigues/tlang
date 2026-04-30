(* tests/package_manager/test_agent_scaffold.ml *)
(* Unit tests for AI agent onboarding scaffolding *)

open Scaffold

let run_tests pass_count fail_count _eval_string _eval_string_env _test =
  Printf.printf "Package Manager — Agent Onboarding:\n";

  let test_pm name check =
    if check () then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  ✗ %s\n" name
    end
  in

  Random.self_init ();
  let base_dir =
    Filename.concat
      (Filename.get_temp_dir_name ())
      (Printf.sprintf "tlang-agent-test-%d-%06d" (Unix.getpid ()) (Random.int 1_000_000))
  in

  let cleanup () =
    let rec remove_path path =
      if Sys.file_exists path then
        if Sys.is_directory path then begin
          Sys.readdir path |> Array.iter (fun name -> remove_path (Filename.concat path name));
          Unix.rmdir path
        end else
          Sys.remove path
    in
    remove_path base_dir
  in

  Fun.protect
    ~finally:cleanup
    (fun () ->
      Unix.mkdir base_dir 0o755;
      let agents_src = Filename.concat base_dir "agents_src" in
      let project_dest = Filename.concat base_dir "project_dest" in
      Unix.mkdir agents_src 0o755;
      Unix.mkdir project_dest 0o755;

      (* Create mock agent files *)
      let write_mock f content =
        let oc = open_out (Filename.concat agents_src f) in
        output_string oc content;
        close_out oc
      in
      write_mock "agents-project.md" "Project Guide";
      write_mock "agents-package.md" "Package Guide";
      write_mock "t-reference-small.md" "Small Ref";
      write_mock "t-reference-medium.md" "Medium Ref";

      (* Set environment variable to point to our mock agents folder *)
      let old_agents_dir = Sys.getenv_opt "TLANG_AGENTS_DIR" in
      Unix.putenv "TLANG_AGENTS_DIR" agents_src;

      let restore_env () =
        match old_agents_dir with
        | Some v -> Unix.putenv "TLANG_AGENTS_DIR" v
        | None -> Unix.putenv "TLANG_AGENTS_DIR" ""
      in

      Fun.protect
        ~finally:restore_env
        (fun () ->
          (* Test 1: Project with medium context *)
          test_pm "copy_agent_files project-medium" (fun () ->
            let ok = copy_agent_files project_dest false "medium" in
            let agents_content =
              let ic = open_in (Filename.concat project_dest "AGENTS.md") in
              let s = really_input_string ic (in_channel_length ic) in
              close_in ic; s
            in
            let ref_content =
              let ic = open_in (Filename.concat project_dest "T-LANGUAGE-REFERENCE.md") in
              let s = really_input_string ic (in_channel_length ic) in
              close_in ic; s
            in
            ok && agents_content = "Project Guide" && ref_content = "Medium Ref"
          );

          (* Test 2: Package with small context *)
          let package_dest = Filename.concat base_dir "package_dest" in
          Unix.mkdir package_dest 0o755;
          test_pm "copy_agent_files package-small" (fun () ->
            let ok = copy_agent_files package_dest true "small" in
            let agents_content =
              let ic = open_in (Filename.concat package_dest "AGENTS.md") in
              let s = really_input_string ic (in_channel_length ic) in
              close_in ic; s
            in
            let ref_content =
              let ic = open_in (Filename.concat package_dest "T-LANGUAGE-REFERENCE.md") in
              let s = really_input_string ic (in_channel_length ic) in
              close_in ic; s
            in
            ok && agents_content = "Package Guide" && ref_content = "Small Ref"
          );

          (* Test 3: .gitignore update *)
          test_pm "gitignore updated with reference" (fun () ->
            let gitignore = Filename.concat project_dest ".gitignore" in
            let ic = open_in gitignore in
            let s = really_input_string ic (in_channel_length ic) in
            close_in ic;
            String.contains s 'T' && String.contains s '-'
          )
        );
      print_newline ()
    )
