open Ast

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
  let get_arg name pos default named_args =
    match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
    | Some v -> (true, v)
    | None ->
        let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
        if List.length positionals >= pos then (true, List.nth positionals (pos - 1))
        else (false, default)
  in
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
      match get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
        let (verbose_provided, verbose_val) = get_arg "verbose" 2 (VNA NAGeneric) named_args in
        let (_, nix_options_val) = get_arg "nix_options" 3 (VDict []) named_args in
        let (dry_run_provided, dry_run_val) = get_arg "dry_run" 4 (VNA NAGeneric) named_args in

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
        let (pipeline_name_provided, pipeline_name_val) = get_arg "pipeline_name" 5 (VNA NAGeneric) named_args in
        let pipeline_name_result =
          match pipeline_name_val with
          | VString s -> Ok (Some s)
          | VSymbol s -> Ok (Some s)
          | VNA _ -> Ok None
          | _ when pipeline_name_provided ->
              Error (Error.type_error "Function `build_pipeline` expects `pipeline_name` to be a String.")
          | _ -> Ok None
        in

        (match verbose_result, nix_options_result, dry_run_result, pipeline_name_result with
         | Error e, _, _, _ | _, Error e, _, _ | _, _, Error e, _ | _, _, _, Error e -> e
         | Ok verbose, Ok nix_options, Ok dry_opt, Ok pipeline_name ->
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
              (* Trigger a final resolution pass to catch typos or unresolved cross-pipeline deps *)
              (match rerun_pipeline ?strict:(Some true) ~verbose:false env p with
               | VPipeline p_resolved ->
                     let pipeline_name =
                       match pipeline_name with
                       | Some _ -> pipeline_name
                       | None ->
                           match Env.fold (fun k val_v acc ->
                             match val_v with
                             | VPipeline p' when p'.p_exprs = p.p_exprs -> Some k
                             | _ -> acc
                           ) env None with
                           | Some name -> Some name
                           | None -> None
                     in
                     (match Builder.populate_pipeline ~build:true ?verbose ?pipeline_name ?nix_options:final_nix_options p_resolved with
                       | Ok (VDataFrame _ as df) -> df
                       | Ok (VDict pairs) ->
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
                           let var_name = match pipeline_name with Some n -> n | None -> "p" in
                           if built = 0 then begin
                             Printf.eprintf "\n  - All nodes up to date — no build needed.\n%!";
                             VNA NAGeneric
                           end else begin
                             let first_node =
                               match p_resolved.p_nodes with
                               | (name, _) :: _ -> name
                               | [] -> "my_node"
                             in
                             Printf.eprintf "\nPipeline successfully built!\n";
                             Printf.eprintf "  - Pipeline saved in variable '%s'\n" var_name;
                             Printf.eprintf "  - To read the contents of node '%s', use: read_node(%s.%s)\n" first_node var_name first_node;
                             Printf.eprintf "  - To inspect node metadata, use: inspect_node(%s.%s)\n" var_name first_node;
                             Printf.eprintf "  - To view pipeline summary, use: inspect_pipeline(%s)\n\n%!" var_name;
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
                           end
                       | Ok other -> other
                     | Error msg -> Error.make_error StructuralError msg)
              | VError _ as err -> err
              | other ->
                  Error.make_error RuntimeError
                    ("build_pipeline expected pipeline resolution to return a Pipeline or Error, but got: "
                     ^ Utils.value_to_string other)))
      | _ -> Error.type_error "Function `build_pipeline` expects a Pipeline."
  in
  Env.add "build_pipeline" (make_builtin_named ~name:"build_pipeline" ~variadic:true 1 build_fn) env
