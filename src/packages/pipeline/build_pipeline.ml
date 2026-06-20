open Ast
open Pipeline_utils

let write_atelier_diagrams p env =
  if not (Builder_utils.is_atelier_active ()) then ()
  else
    let root = Builder_utils.get_atelier_project_root () in
    Builder_utils.ensure_atelier_dir root;
    (match Env.find_opt "pipeline_to_dot" env with
     | Some (VBuiltin { b_func; _ }) ->
       let args = [(None, VPipeline p)] in
       let env_ref = ref env in
       (try match b_func args env_ref with
            | VString s ->
              Builder_utils.write_file (Builder_utils.atelier_dot_path root) s |> ignore
            | _ -> ()
        with _ -> ())
     | _ -> ());
    (match Env.find_opt "pipeline_to_mermaid" env with
     | Some (VBuiltin { b_func; _ }) ->
       let args = [(None, VPipeline p)] in
       let env_ref = ref env in
       (try match b_func args env_ref with
            | VString s ->
              Builder_utils.write_file (Builder_utils.atelier_mermaid_path root) s |> ignore
            | _ -> ()
        with _ -> ())
     | _ -> ())

(*
--# Build Pipeline Artifacts
--#
--# Builds a pipeline to `pipeline.nix` and records node artifacts in a local registry.
--# Supports Nix-native orchestration flags for targeted builds, cache usage, and dry-runs.
--#
--# @name build_pipeline
--# @param pipeline :: Pipeline The pipeline to build.
--# @param verbose :: Int (Optional) Nix build verbosity level. `0` keeps build failures quiet; values above `0` print failed node logs.
--# @param nix_options :: Dict (Optional) A dictionary of Nix orchestration options:
--#   - `targets` :: List[String] Specific node names to build. Maps to `-A <target>` in nix-build.
--#   - `force` :: Bool|List[String] Force-rebuild nodes even if cached. Maps to `--check`.
--#   - `dry_run` :: Bool Return a planned build DataFrame without executing. Maps to `--dry-run`.
--#   - `max_jobs` :: Int Maximum parallel build jobs. Maps to `--max-jobs N`.
--#   - `cache` :: String Cachix cache name to configure as an extra binary substituter.
--# @return :: BuildLog|DataFrame A structured build log (`nodes`, `duration`, `failed_nodes`, `out_path`), or a dry-run DataFrame.
--# @family pipeline
--# @seealso read_node
--# @export
*)
let register ~(rerun_pipeline : ?strict:bool -> ?verbose:bool -> value Env.t -> pipeline_result -> value) env =
  let build_fn named_args env =
    let named_keys = List.filter_map (fun (k, _) -> k) named_args in
    let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
    match List.find_opt (fun k -> not (List.mem k ["p"; "verbose"; "nix_options"; "dry_run"; "pipeline_name"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "build_pipeline: unknown argument '%s'" k)
    | None when positional_count > 4 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `build_pipeline` accepts at most 4 positional arguments but received %d." positional_count)
    | None ->
      match Pipeline_args.get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
          if p.p_has_patterns then
            Error.make_error StructuralError
              "Pipeline contains unexpanded dynamic branching patterns. Use expand_pipeline(p) to resolve branches before building. See help(expand_pipeline) for details."
          else
            let (verbose_provided, verbose_val) = Pipeline_args.get_arg "verbose" 2 (VNA NAGeneric) named_args in
        let (_, nix_options_val) = Pipeline_args.get_arg "nix_options" 3 (VDict []) named_args in
        let (dry_run_provided, dry_run_val) = Pipeline_args.get_arg "dry_run" 4 (VNA NAGeneric) named_args in

        let verbose_result =
          match verbose_val with
          | VInt i when i >= 0 -> Ok (Some i)
          | VInt _ ->
              Error (Error.value_error "Function `build_pipeline` expects `verbose` to be a non-negative Int.")
          | _ when verbose_provided ->
              Error (Error.type_error "Function `build_pipeline` expects `verbose` to be an Int.")
          | _ ->
              Ok None
        in

        let nix_options_result =
          match nix_options_val with
          | VNA _ -> Ok None
          | VDict pairs ->
              (match Builder_utils.validate_nix_options "build_pipeline" pairs with
               | Ok opts -> Ok (Some opts)
               | Error e -> Error e)
          | _ -> Error (Error.type_error "Function `build_pipeline` expects `nix_options` to be a Dictionary.")
        in

        let dry_run_result =
          match dry_run_val with
          | VBool b -> Ok (Some b)
          | VNA _ -> Ok None
          | _ when dry_run_provided ->
              Error (Error.type_error "Function `build_pipeline` expects `dry_run` to be a Bool.")
          | _ -> Ok None
        in
        let (pipeline_name_provided, pipeline_name_val) = Pipeline_args.get_arg "pipeline_name" 5 (VNA NAGeneric) named_args in
        let pipeline_name_result =
          match pipeline_name_val with
          | VString s -> Ok (Some s)
          | VSymbol s -> Ok (Some s)
          | VNA _ -> Ok None
          | _ when pipeline_name_provided ->
              Error (Error.type_error "Function `build_pipeline` expects `pipeline_name` to be a String.")
          | _ -> Ok None
        in

        let (let*) x f = match x with Ok v -> f v | Error e -> e in
        let* verbose = verbose_result in
        let* nix_options = nix_options_result in
        let* dry_opt = dry_run_result in
        let* pipeline_name = pipeline_name_result in
        let final_nix_options =
          let base_opts =
            match nix_options with
            | Some opts -> opts
            | None -> Builder_utils.default_nix_opts
          in
          match dry_opt with
          | Some d -> Some { base_opts with dry_run = Some d }
          | None -> Some base_opts
        in
        (match rerun_pipeline ?strict:(Some true) ~verbose:false env p with
         | VPipeline p_resolved ->
             let pipeline_name =
               match pipeline_name with
               | Some _ -> pipeline_name
               | None -> resolve_pipeline_name env p
             in
             (match Builder.populate_pipeline ~build:true ?verbose ?pipeline_name ?nix_options:final_nix_options p_resolved with
              | Ok (VDataFrame _ as df) ->
                  write_atelier_diagrams p_resolved env;
                  df
              | Ok (VDict pairs as out) ->
                  write_atelier_diagrams p_resolved env;
                  let out_path =
                    match List.assoc_opt "out_path" pairs with
                    | Some (VString s) -> s
                    | _ -> ""
                  in
                  let built =
                    match List.assoc_opt "built" pairs with
                    | Some (VInt n) -> n
                    | _ -> 0
                  in
                  let soft_failed =
                    match List.assoc_opt "soft_failed" pairs with
                    | Some (VList items) -> List.length items
                    | _ -> 0
                  in
                  let var_name = match pipeline_name with Some n -> n | None -> "p" in
                  let first_node =
                    match p_resolved.p_nodes with
                    | (name, _) :: _ -> name
                    | [] -> "my_node"
                  in
                  if built > 0 then
                    if soft_failed > 0 then
                      Printf.eprintf "\nPipeline built successfully but with errors\n"
                    else
                      Printf.eprintf "\nPipeline successfully built!\n";
                  Printf.eprintf "  - Pipeline saved in variable '%s'\n" var_name;
                  Printf.eprintf "  - To read the contents of node '%s', use: read_node(%s.%s)\n" first_node var_name first_node;
                  Printf.eprintf "  - To inspect node metadata, use: inspect_node(%s.%s)\n" var_name first_node;
                  Printf.eprintf "  - To view pipeline summary, use: inspect_pipeline(%s)\n\n%!" var_name;
                  if built > 0 then
                    (match Builder.find_log_for_out_path out_path with
                     | Some log_path ->
                         Hashtbl.replace Ast.pipeline_build_logs p.p_exprs log_path;
                         Hashtbl.replace Ast.pipeline_build_logs p_resolved.p_exprs log_path;
                         Builder.parse_json_log_to_vbuildlog log_path
                     | None ->
                         Error.make_error FileError
                           (Printf.sprintf
                              "No build log matching output path `%s` was found after build completed."
                              out_path))
                  else
                    out
              | Ok other -> other
              | Error msg -> Error.make_error StructuralError msg)
         | VError _ as err -> err
         | other ->
             Error.make_error RuntimeError
               ("build_pipeline expected pipeline resolution to return a Pipeline or Error, but got: "
                ^ Utils.value_to_string other))
      | _ -> Error.type_error "Function `build_pipeline` expects a Pipeline."
  in
  Env.add "build_pipeline" (make_builtin_named ~name:"build_pipeline" ~variadic:true 1 build_fn) env
