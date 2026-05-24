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
    match List.find_opt (fun k -> not (List.mem k ["p"; "verbose"; "nix_options"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "build_pipeline: unknown argument '%s'" k)
    | None when positional_count > 3 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `build_pipeline` accepts at most 3 positional arguments but received %d." positional_count)
    | None ->
      match get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
        let (verbose_provided, verbose_val) = get_arg "verbose" 2 (VNA NAGeneric) named_args in
        let (_, nix_options_val) = get_arg "nix_options" 3 (VDict []) named_args in

        let nix_options_result =
          match nix_options_val with
          | VNA _ -> Ok []
          | VDict pairs -> Ok pairs
          | _ -> Error (Error.type_error "Function `build_pipeline` expects `nix_options` to be a Dictionary.")
        in

        (match nix_options_result with
         | Error e -> e
         | Ok pairs ->
             match List.find_opt (fun (k, _) -> not (List.mem k ["targets"; "force"; "dry_run"; "max_jobs"; "cache"; "builders"])) pairs with
             | Some (k, _) ->
                 Error.type_error (Printf.sprintf "build_pipeline: unknown option '%s' in nix_options" k)
             | None ->
                 let targets_val = match List.assoc_opt "targets" pairs with Some v -> v | None -> VNA NAGeneric in
                 let targets_provided = match List.assoc_opt "targets" pairs with Some (VNA _) -> false | Some _ -> true | None -> false in
                 let force_val = match List.assoc_opt "force" pairs with Some v -> v | None -> VNA NAGeneric in
                 let force_provided = match List.assoc_opt "force" pairs with Some (VNA _) -> false | Some _ -> true | None -> false in
                 let dry_run_val = match List.assoc_opt "dry_run" pairs with Some v -> v | None -> VNA NAGeneric in
                 let dry_run_provided = match List.assoc_opt "dry_run" pairs with Some (VNA _) -> false | Some _ -> true | None -> false in
                 let max_jobs_val = match List.assoc_opt "max_jobs" pairs with Some v -> v | None -> VNA NAGeneric in
                 let max_jobs_provided = match List.assoc_opt "max_jobs" pairs with Some (VNA _) -> false | Some _ -> true | None -> false in
                 let cache_val = match List.assoc_opt "cache" pairs with Some v -> v | None -> VNA NAGeneric in
                 let cache_provided = match List.assoc_opt "cache" pairs with Some (VNA _) -> false | Some _ -> true | None -> false in
                 let builders_val = match List.assoc_opt "builders" pairs with Some v -> v | None -> VNA NAGeneric in
                 let builders_provided = match List.assoc_opt "builders" pairs with Some (VNA _) -> false | Some _ -> true | None -> false in

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
                 let targets_result =
                   match targets_val with
                   | VString _ -> Ok (Some targets_val)
                   | VList items ->
                       if List.exists (function (_, VString _) -> false | _ -> true) items then
                         Error (Error.type_error "Function `build_pipeline` expects `targets` to contain only String values.")
                       else Ok (Some targets_val)
                   | VVector arr ->
                       if Array.exists (function VString _ -> false | _ -> true) arr then
                         Error (Error.type_error "Function `build_pipeline` expects `targets` to contain only String values.")
                       else Ok (Some targets_val)
                   | _ when targets_provided ->
                       Error (Error.type_error "Function `build_pipeline` expects `targets` to be a String, List, or Vector.")
                   | _ -> Ok None
                 in
                 let force_result =
                   match force_val with
                   | VBool _ | VList _ | VVector _ | VString _ -> Ok (Some force_val)
                   | _ when force_provided ->
                       Error (Error.type_error "Function `build_pipeline` expects `force` to be a Bool, String, List, or Vector.")
                   | _ -> Ok None
                 in
                 let dry_run_result =
                   match dry_run_val with
                   | VBool b -> Ok (Some b)
                   | _ when dry_run_provided ->
                       Error (Error.type_error "Function `build_pipeline` expects `dry_run` to be a Bool.")
                   | _ -> Ok None
                 in
                 let max_jobs_result =
                   match max_jobs_val with
                   | VInt n when n > 0 -> Ok (Some max_jobs_val)
                   | _ when max_jobs_provided ->
                       Error (Error.type_error "Function `build_pipeline` expects `max_jobs` to be a positive Int.")
                   | _ -> Ok None
                 in
                 let cache_result =
                   match cache_val with
                   | VString _ -> Ok (Some cache_val)
                   | _ when cache_provided ->
                       Error (Error.type_error "Function `build_pipeline` expects `cache` to be a String.")
                   | _ -> Ok None
                 in
                 let builders_result =
                   match builders_val with
                   | VString _ -> Ok (Some builders_val)
                   | _ when builders_provided ->
                       Error (Error.type_error "Function `build_pipeline` expects `builders` to be a String.")
                   | _ -> Ok None
                 in
                 (match verbose_result, targets_result, force_result, dry_run_result, max_jobs_result, cache_result, builders_result with
                  | Error e, _, _, _, _, _, _
                  | _, Error e, _, _, _, _, _
                  | _, _, Error e, _, _, _, _
                  | _, _, _, Error e, _, _, _
                  | _, _, _, _, Error e, _, _
                  | _, _, _, _, _, Error e, _
                  | _, _, _, _, _, _, Error e -> e
                  | Ok verbose, Ok targets, Ok force, Ok dry_run, Ok max_jobs, Ok cache, Ok builders ->
                      (* Trigger a final resolution pass to catch typos or unresolved cross-pipeline deps *)
                      (match rerun_pipeline ?strict:(Some true) ~verbose:false env p with
                       | VPipeline p_resolved ->
                             (match Builder.populate_pipeline ~build:true ?verbose ?targets ?force ?dry_run ?max_jobs ?cache ?builders p_resolved with
                              | Ok (VDataFrame _ as df) -> df
                              | Ok (VString out_path) ->
                                  let var_name =
                                    match Env.fold (fun k val_v acc ->
                                      match val_v with
                                      | VPipeline p' when p'.p_exprs = p_resolved.p_exprs -> Some k
                                      | _ -> acc
                                    ) env None with
                                    | Some name -> name
                                    | None -> "p"
                                  in
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
                                   | Some log_path -> Builder.parse_json_log_to_vbuildlog log_path
                                   | None ->
                                       Error.make_error FileError
                                         (Printf.sprintf
                                            "No build log matching output path `%s` was found after build completed."
                                            out_path))
                              | Ok other -> other
                             | Error msg -> Error.make_error StructuralError msg)
                       | VError _ as err -> err
                       | other ->
                           Error.make_error RuntimeError
                             ("build_pipeline expected pipeline resolution to return a Pipeline or Error, but got: "
                              ^ Utils.value_to_string other))))
      | _ -> Error.type_error "Function `build_pipeline` expects a Pipeline."
  in
  Env.add "build_pipeline" (make_builtin_named ~name:"build_pipeline" ~variadic:true 1 build_fn) env
