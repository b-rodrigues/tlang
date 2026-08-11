(* src/pipeline/builder_populate.ml *)
open Builder_utils
open Builder_write_dag
open Builder_internal
open Package_types

let builtin_pipeline_strategies =
  [ "pmml"; "ipc"; "parquet"; "json"; "csv"; "default"; "onnx"; "bin"; "text" ]

let cold_start_warning_shown = ref false

let generate_nix (p : Ast.pipeline_result) =
  ensure_pipeline_dir ();
  match write_dag p with
  | Error msg -> Error ("Failed to write dag.json: " ^ msg)
  | Ok () ->
      let rel_root = 
        match get_relative_path_to_root () with
        | "." -> ".."
        | r -> "../" ^ r
      in
      let project_root = Builder_utils.get_project_root () in
      let r_renv_cran_pkgs, r_git_pkgs, py_version_opt, use_uv =
        let tproject_path = Filename.concat project_root "tproject.toml" in
        if Sys.file_exists tproject_path then
          (try
             let ch = open_in tproject_path in
             let content =
               Fun.protect
                 ~finally:(fun () -> close_in_noerr ch)
                 (fun () -> really_input_string ch (in_channel_length ch))
             in
             match Toml_parser.parse_tproject_toml ~root_dir:project_root content with
             | Ok cfg ->
               let toml_git_pkgs =
                 R_description_resolver.auto_detect_all
                   ~cache_root:(Filename.concat project_root ".t_r_pkg_cache")
                   ~deps:cfg.proj_r_git_dependencies
               in
               let cran_pkgs, git_pkgs =
                 if cfg.proj_r_resolver = "renv" then
                   match Renv_resolver.split_packages ~project_root with
                   | Ok (renv_cran, renv_git) -> renv_cran, toml_git_pkgs @ renv_git
                   | Error _ -> [], toml_git_pkgs
                 else
                   [], toml_git_pkgs
               in
               cran_pkgs, git_pkgs, Some cfg.proj_py_version, cfg.proj_py_resolver = "uv"
             | Error _ -> [], [], None, false
           with _ -> [], [], None, false)
        else [], [], None, false
      in
      let r_serializer_packages, py_serializer_packages =
        Pipeline_dependency_requirements.required_serializer_packages p
      in
      let nix_content =
        Nix_emitter.emit_pipeline ~rel_root ~r_git_pkgs ~r_renv_cran_pkgs
          ?py_version:py_version_opt ~r_serializer_packages ~py_serializer_packages p
      in
      match write_file pipeline_nix_path nix_content with
      | Error msg -> Error ("Failed to write pipeline.nix: " ^ msg)
      | Ok () -> Ok (use_uv, pipeline_nix_path)

let generate_and_maybe_build ?verbose ?pipeline_name ?nix_options ~build (p : Ast.pipeline_result) =
  match generate_nix p with
  | Error msg -> Error msg
  | Ok (use_uv, _nix_path) ->
      if build then
        let has_per_node_flakes = List.exists (fun (_, f) -> f <> None) p.p_flakes in
        if (has_per_node_flakes || use_uv) && not !cold_start_warning_shown then (
          cold_start_warning_shown := true;
          Printf.eprintf
            "\n\
             This pipeline uses per-node flakes or UV Python workspaces.\n\
             The first build will download and compile all dependencies.\n\
             This is a one-time cold-start cost — subsequent runs will be\n\
             significantly faster. Go grab a coffee ☕\n\
             \n%!"
        );
        (match build_pipeline_internal ?verbose ?pipeline_name ?nix_options ~json:!Ast.ndjson_mode p with
         | Ok result -> Ok result
         | Error msg -> Error msg)
      else Ok (Ast.VString (Printf.sprintf "Pipeline populated in `%s`" pipeline_dir))

let populate_pipeline ?(build=false) ?(skip_requirements=false) ?verbose ?pipeline_name ?(nix_options : nix_opts option) (p : Ast.pipeline_result) =
  match Pipeline_validation.check_missing_files p with
  | first :: _ -> Error first.Pipeline_validation.ve_message
  | [] ->
  if not skip_requirements then begin
    match Pipeline_dependency_requirements.ensure_project_requirements p with
    | Error msg -> Error ("Pipeline dependency check failed: " ^ msg)
    | Ok () ->
    let () =
      let eval_string_list lst =
        lst
        |> List.map (Eval.eval_expr (ref (Ast.Env.empty)))
        |> List.map (function Ast.VString s -> s | _ -> "")
        |> List.filter (fun s -> s <> "")
      in
      List.iter (fun (name, _) ->
        let ser = match List.assoc_opt name p.p_serializers with Some s -> s | None -> Ast.mk_expr (Ast.Var "default") in
        let des = match List.assoc_opt name p.p_deserializers with Some e -> e | None -> Ast.mk_expr (Ast.Var "default") in
        let funcs = match List.assoc_opt name p.p_functions with Some f -> eval_string_list f | None -> [] in
        let rec check_serializer_type expr =
          match expr.Ast.node with
          | Ast.Value (Ast.VString s) when List.mem (String.lowercase_ascii s) (builtin_pipeline_strategies @ ["serialize"]) ->
              Printf.eprintf "Warning: Node `%s` uses a string literal for a built-in serializer (\"%s\").\nPlease use a symbol instead, e.g.: serializer = ^%s\n%!" 
                name s (if s = "serialize" then "default" else s)
          | Ast.ListLit items -> List.iter (fun (_, e) -> check_serializer_type e) items
          | Ast.DictLit items -> List.iter (fun (_, e) -> check_serializer_type e) items
          | _ -> ()
        in
        check_serializer_type ser;
        
        let rec requires_functions expr =
          match expr.Ast.node with
          | Ast.Value (Ast.VSymbol s) -> 
              let s = if String.starts_with ~prefix:"^" s then String.sub s 1 (String.length s - 1) else s in
              not (List.mem s builtin_pipeline_strategies)
          | Ast.Value (Ast.VSerializer s) ->
              not (List.mem s.s_format builtin_pipeline_strategies)
          | Ast.Value (Ast.VString _) -> true
          | Ast.Var _ -> false
          | Ast.DotAccess _ | Ast.RawCode _ -> false
          | Ast.ListLit items -> List.exists (fun (_, e) -> requires_functions e) items
          | Ast.DictLit items -> List.exists (fun (_, e) -> requires_functions e) items
          | _ -> false
        in
        let is_custom_ser = requires_functions ser in
        let is_custom_des = requires_functions des in
        if (is_custom_ser || is_custom_des) && funcs = [] then
          Printf.eprintf "Warning: Node `%s` uses a custom or unknown strategy (not 'default', 'csv', 'json', 'ipc', 'parquet', 'pmml', 'onnx', etc.) but has no supporting `functions` specified.\nIf this is a built-in strategy, check the spelling (e.g., ^ipc or ^parquet).\nIf it is a custom function, ensure it is available in the runtime environment.\n%!" name
      ) p.p_exprs
    in

    match Pipeline_validation.serializer_errors p with
    | first :: _ -> Error first.Pipeline_validation.ve_message
    | [] ->
      generate_and_maybe_build ?verbose ?pipeline_name ?nix_options ~build p
  end else
    generate_and_maybe_build ?verbose ?pipeline_name ?nix_options ~build p
