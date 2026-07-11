(* src/env_check.ml *)
(* Tier 3 environment checks for t check --env *)

(* Check required packages are declared in tproject.toml *)
let check_declared_requirements ~file (p : Ast.pipeline_result) =
  let project_root = Builder_utils.get_project_root () in
  let tproject_path = Filename.concat project_root "tproject.toml" in
  if not (Sys.file_exists tproject_path) then begin
    let required = Pipeline_dependency_requirements.required_for_pipeline p in
    let has_any_requirements =
      not (Pipeline_dependency_requirements.String_set.is_empty required.r_deps)
      || not (Pipeline_dependency_requirements.String_set.is_empty required.py_deps)
      || not (Pipeline_dependency_requirements.String_set.is_empty required.julia_deps)
      || not (Pipeline_dependency_requirements.String_set.is_empty required.additional_tools)
      || not (Pipeline_dependency_requirements.String_set.is_empty required.latex_pkgs)
    in
    if has_any_requirements then
      [Diagnostics.{
        diag_id = Diagnostics.gen_id ();
        diag_error_class = "missing_tproject";
        diag_severity = Error;
        diag_phase = Env;
        diag_node_id = None;
        diag_node_lang = None;
        diag_file = Some file;
        diag_line = None;
        diag_column = None;
        diag_message = Printf.sprintf "Pipeline requires R/Python/Julia packages but tproject.toml not found at %s" tproject_path;
        diag_caused_by = [];
        diag_suggested_fix = NoFix;
      }]
    else []
  end else begin
    match Pipeline_dependency_requirements.analyze_missing_requirements_with_renv p ~project_root with
    | None -> []
    | Some analysis ->
        let missing_diags = ref [] in
        let add_missing section pkgs =
          List.iter (fun pkg ->
            missing_diags := Diagnostics.{
              diag_id = Diagnostics.gen_id ();
              diag_error_class = "missing_package";
              diag_severity = Error;
              diag_phase = Env;
              diag_node_id = None;
              diag_node_lang = None;
              diag_file = Some file;
              diag_line = None;
              diag_column = None;
              diag_message = Printf.sprintf "Package '%s' required by pipeline not declared in %s %s" pkg tproject_path section;
              diag_caused_by = [];
              diag_suggested_fix = NoFix;
            } :: !missing_diags
          ) pkgs
        in
        add_missing "[r-dependencies]" analysis.Pipeline_dependency_requirements.missing_r_deps;
        add_missing "[py-dependencies]" analysis.Pipeline_dependency_requirements.missing_py_deps;
        add_missing "[jl-dependencies]" analysis.Pipeline_dependency_requirements.missing_julia_deps;
        add_missing "[additional-tools]" analysis.Pipeline_dependency_requirements.missing_additional_tools;
        add_missing "[latex]" analysis.Pipeline_dependency_requirements.missing_latex_pkgs;
        !missing_diags
  end

(* Check lockfile consistency: for renv, verify CRAN packages are in renv.lock *)
let check_lockfile_consistency ~file (p : Ast.pipeline_result) =
  let project_root = Builder_utils.get_project_root () in
  let tproject_path = Filename.concat project_root "tproject.toml" in
  if not (Sys.file_exists tproject_path) then [] else
  let content =
    let ch = open_in tproject_path in
    Fun.protect ~finally:(fun () -> close_in_noerr ch)
      (fun () -> really_input_string ch (in_channel_length ch))
  in
  match Toml_parser.parse_tproject_toml ~root_dir:project_root content with
  | Error _ -> []
  | Ok cfg ->
    if cfg.Package_types.proj_r_resolver <> "renv" then [] else
    match Renv_resolver.split_packages ~project_root with
    | Error _ -> []
    | Ok (cran_pkgs, _git_pkgs) ->
        let required = Pipeline_dependency_requirements.required_for_pipeline p in
        let renv_set = List.fold_left (fun s pkg -> Pipeline_dependency_requirements.String_set.add pkg s)
          Pipeline_dependency_requirements.String_set.empty cran_pkgs in
        let missing = Pipeline_dependency_requirements.String_set.diff required.r_deps renv_set
          |> Pipeline_dependency_requirements.String_set.elements in
        List.map (fun pkg ->
          Diagnostics.{
            diag_id = Diagnostics.gen_id ();
            diag_error_class = "missing_from_lockfile";
            diag_severity = Error;
            diag_phase = Env;
            diag_node_id = None;
            diag_node_lang = None;
            diag_file = Some file;
            diag_line = None;
            diag_column = None;
            diag_message = Printf.sprintf "R package '%s' required by pipeline not found in renv.lock" pkg;
            diag_caused_by = [];
            diag_suggested_fix = NoFix;
          }
        ) missing

(* Validate Nix evaluation via nix-instantiate --eval *)
let check_nix_evaluation ~file (p : Ast.pipeline_result) =
  let nix_path = Builder_utils.pipeline_nix_path in
  if not (Sys.file_exists nix_path) then [] else
  let node_names = List.map fst p.Ast.p_exprs in
  if node_names = [] then [] else
  let assignments =
    List.map (fun name ->
      let parts = String.split_on_char '.' name in
      let quoted_path = List.map (fun part -> Printf.sprintf "\"%s\"" part) parts |> String.concat "." in
      Printf.sprintf "\"%s\" = toString p.%s;" name quoted_path
    ) node_names
    |> String.concat " "
  in
  let expr = Printf.sprintf "let p = import ./%s {}; in { %s }" nix_path assignments in
  let argv = [| "nix-instantiate"; "--impure"; "--eval"; "--strict"; "--expr"; expr |] in
  match Builder_utils.run_command_argv_capture argv with
  | Ok _output -> []
  | Error msg ->
      [Diagnostics.{
        diag_id = Diagnostics.gen_id ();
        diag_error_class = "nix_eval_error";
        diag_severity = Error;
        diag_phase = Env;
        diag_node_id = None;
        diag_node_lang = None;
        diag_file = Some file;
        diag_line = None;
        diag_column = None;
        diag_message = Printf.sprintf "Nix expression evaluation failed: %s" msg;
        diag_caused_by = [];
        diag_suggested_fix = NoFix;
      }]

(* Main entry point: run all tier 3 env checks *)
let check_env ~file (p : Ast.pipeline_result) =
  let declared_diags = check_declared_requirements ~file p in
  let lockfile_diags = check_lockfile_consistency ~file p in
  declared_diags @ lockfile_diags
