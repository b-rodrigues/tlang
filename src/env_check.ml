(* src/env_check.ml *)
(* Tier 3 environment checks for t check --env *)

(* Shared: parse tproject.toml once *)
let parse_tproject ~project_root =
  let tproject_path = Filename.concat project_root "tproject.toml" in
  if not (Sys.file_exists tproject_path) then None
  else
    let content =
      let ch = open_in tproject_path in
      Fun.protect ~finally:(fun () -> close_in_noerr ch)
        (fun () -> really_input_string ch (in_channel_length ch))
    in
    match Toml_parser.parse_tproject_toml ~root_dir:project_root content with
    | Ok cfg -> Some cfg
    | Error _ -> None

(* Check required packages are declared in tproject.toml *)
let check_declared_requirements ~file ~tproject_path ~project_root ~tproject_cfg (p : Ast.pipeline_result) =
  match tproject_cfg with
  | None ->
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
  | Some cfg ->
    let cfg =
      if cfg.Package_types.proj_r_resolver = "renv" then
        match Renv_resolver.split_packages ~project_root with
        | Ok (renv_cran, renv_git) ->
            { cfg with
              Package_types.proj_r_dependencies = cfg.proj_r_dependencies @ renv_cran;
              proj_r_git_dependencies = cfg.proj_r_git_dependencies @ renv_git;
            }
        | Error _ -> cfg
      else cfg
    in
    let analysis = Pipeline_dependency_requirements.analyze_missing_requirements p cfg in
    if Pipeline_dependency_requirements.analysis_is_empty analysis then []
    else
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

(* Check lockfile consistency: for renv, verify all required packages are in renv.lock *)
let check_lockfile_consistency ~file ~tproject_cfg (p : Ast.pipeline_result) =
  match tproject_cfg with
  | Some cfg when cfg.Package_types.proj_r_resolver = "renv" ->
    let project_root = Builder_utils.get_project_root () in
    (match Renv_resolver.split_packages ~project_root with
     | Error _ -> []
     | Ok (cran_pkgs, git_pkgs) ->
         let required = Pipeline_dependency_requirements.required_for_pipeline p in
         let renv_set = List.fold_left (fun s pkg -> Pipeline_dependency_requirements.String_set.add pkg s)
           Pipeline_dependency_requirements.String_set.empty cran_pkgs in
         let renv_set = List.fold_left (fun s (git_pkg : Package_types.r_git_dependency) ->
           Pipeline_dependency_requirements.String_set.add git_pkg.Package_types.rgd_name s
         ) renv_set git_pkgs in
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
         ) missing)
  | _ -> []

(* Validate Nix evaluation via nix eval *)
let check_nix_evaluation ?(offline = false) ~file (p : Ast.pipeline_result) =
  match Builder_populate.generate_nix p with
  | Error msg ->
      [Diagnostics.{
        diag_id = Diagnostics.gen_id ();
        diag_error_class = "nix_generation_error";
        diag_severity = Error;
        diag_phase = Env;
        diag_node_id = None;
        diag_node_lang = None;
        diag_file = Some file;
        diag_line = None;
        diag_column = None;
        diag_message = Printf.sprintf "Failed to generate pipeline.nix for evaluation: %s" msg;
        diag_caused_by = [];
        diag_suggested_fix = NoFix;
      }]
  | Ok (_use_uv, nix_path) ->
      let node_names = List.map fst p.Ast.p_exprs in
      if node_names = [] then [] else
      let assignments =
        List.map (fun name ->
          let parts = String.split_on_char '.' name in
          let quoted_path = List.map (fun part -> Printf.sprintf "\"%s\"" part) parts |> String.concat "." in
          (* toString p.<name> produces a string; the resulting attrset is trivially JSON-encodable *)
          Printf.sprintf "\"%s\" = toString p.%s;" name quoted_path
        ) node_names
        |> String.concat " "
      in
      let expr = Printf.sprintf "let p = import ./%s {}; in { %s }" nix_path assignments in
      let argv =
        if offline then
          [| "nix"; "eval"; "--offline"; "--impure"; "--json"; "--expr"; expr |]
        else
          [| "nix"; "eval"; "--impure"; "--json"; "--expr"; expr |]
      in
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
let check_env ?(offline = false) ~file (p : Ast.pipeline_result) =
  let project_root = Builder_utils.get_project_root () in
  let tproject_path = Filename.concat project_root "tproject.toml" in
  let tproject_cfg = parse_tproject ~project_root in
  let declared_diags = check_declared_requirements ~file ~tproject_path ~project_root ~tproject_cfg p in
  let lockfile_diags = check_lockfile_consistency ~file ~tproject_cfg p in
  let nix_diags = check_nix_evaluation ~offline ~file p in
  declared_diags @ lockfile_diags @ nix_diags
