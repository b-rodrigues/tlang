open Ast

(*
--# Populate Pipeline
--#
--# Generates the `_pipeline/` directory with `pipeline.nix` and `dag.json`.
--# Optionally builds the pipeline with full Nix-native orchestration support.
--#
--# @name populate_pipeline
--# @param p :: Pipeline The pipeline to populate.
--# @param build :: Bool (Optional) Whether to trigger the Nix build immediately. Defaults to false.
--# @param verbose :: Int (Optional) Nix build verbosity level. `0` keeps build failures quiet; values above `0` print failed node logs.
--# @param nix_options :: Dict (Optional) A dictionary of Nix orchestration options:
--#   - `targets` :: List[String] Specific node names to build. Maps to `-A <target>` in nix-build.
--#   - `force` :: Bool|List[String] Force-rebuild nodes even if cached. Maps to `--check`.
--#   - `dry_run` :: Bool Return a planned build DataFrame without executing. Maps to `--dry-run`.
--#   - `max_jobs` :: Int Maximum parallel build jobs. Maps to `--max-jobs N`.
--#   - `cache` :: String Cachix cache name to configure as an extra binary substituter.
--# @return :: String|BuildLog|DataFrame A status message, structured build log, or dry-run plan DataFrame.
--# @note `populate_pipeline` performs several validation checks before generating the Nix files:
--#   - **File Existence**: Verifies that all files specified in `functions` or `include` arguments of any node actually exist on the file system.
--#   - **Custom Function Warning**: Issues a warning to `stderr` if a node uses a custom `serializer` or `deserializer` but does not provide any companion `functions` files.
--#   - **Explicit Dependency Declaration**: Checks serializer/runtime requirements up front and asks to add missing entries to `tproject.toml` instead of injecting packages implicitly.
--# @family pipeline
--# @export
*)
let register env =
  let populate_fn named_args env =
    let get_arg name pos default named_args =
      match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
      | Some v -> (true, v)
      | None ->
          let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
          if List.length positionals >= pos then (true, List.nth positionals (pos - 1))
          else (false, default)
    in
    let named_keys = List.filter_map (fun (k, _) -> k) named_args in
    let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
    match List.find_opt (fun k -> not (List.mem k ["p"; "build"; "verbose"; "nix_options"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "populate_pipeline: unknown argument '%s'" k)
    | None when positional_count > 4 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `populate_pipeline` accepts at most 4 positional arguments but received %d." positional_count)
    | None ->
      match get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
        let (build_provided, build_val) = get_arg "build" 2 (VBool false) named_args in
        let (verbose_provided, verbose_val) = get_arg "verbose" 3 (VNA NAGeneric) named_args in
        let (_, nix_options_val) = get_arg "nix_options" 4 (VDict []) named_args in

        let nix_options_result =
          match nix_options_val with
          | VNA _ -> Ok []
          | VDict pairs -> Ok pairs
          | _ -> Error (Error.type_error "Function `populate_pipeline` expects `nix_options` to be a Dictionary.")
        in

        (match nix_options_result with
         | Error e -> e
         | Ok pairs ->
             match List.find_opt (fun (k, _) -> not (List.mem k ["targets"; "force"; "dry_run"; "max_jobs"; "cache"; "builders"; "keep_env"; "sandbox"])) pairs with
             | Some (k, _) ->
                 Error.type_error (Printf.sprintf "populate_pipeline: unknown option '%s' in nix_options" k)
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
                 let keep_env_val = match List.assoc_opt "keep_env" pairs with Some v -> v | None -> VNA NAGeneric in
                 let keep_env_provided = match List.assoc_opt "keep_env" pairs with Some (VNA _) -> false | Some _ -> true | None -> false in
                 let sandbox_val = match List.assoc_opt "sandbox" pairs with Some v -> v | None -> VNA NAGeneric in
                 let sandbox_provided = match List.assoc_opt "sandbox" pairs with Some (VNA _) -> false | Some _ -> true | None -> false in

                 let build_result =
                   match build_val with
                   | VBool b -> Ok b
                   | _ when build_provided ->
                       Error (Error.type_error "Function `populate_pipeline` expects `build` to be a Bool.")
                   | _ ->
                       Ok false
                 in
                 let verbose_result =
                   match verbose_val with
                   | VInt i when i >= 0 -> Ok (Some i)
                   | VInt _ ->
                       Error (Error.value_error "Function `populate_pipeline` expects `verbose` to be a non-negative Int.")
                   | _ when verbose_provided ->
                       Error (Error.type_error "Function `populate_pipeline` expects `verbose` to be an Int.")
                   | _ ->
                       Ok None
                 in
                 let targets_result =
                   match targets_val with
                   | VString _ -> Ok (Some targets_val)
                   | VList items ->
                       if List.exists (function (_, VString _) -> false | _ -> true) items then
                         Error (Error.type_error "Function `populate_pipeline` expects `targets` to contain only String values.")
                       else Ok (Some targets_val)
                   | VVector arr ->
                       if Array.exists (function VString _ -> false | _ -> true) arr then
                         Error (Error.type_error "Function `populate_pipeline` expects `targets` to contain only String values.")
                       else Ok (Some targets_val)
                   | _ when targets_provided ->
                       Error (Error.type_error "Function `populate_pipeline` expects `targets` to be a String, List, or Vector.")
                   | _ -> Ok None
                 in
                 let force_result =
                   match force_val with
                   | VBool _ -> Ok (Some force_val)
                   | VString _ -> Ok (Some force_val)
                   | VList items ->
                       if List.exists (function (_, VString _) -> false | _ -> true) items then
                         Error (Error.type_error "Function `populate_pipeline` expects `force` to contain only String values.")
                       else Ok (Some force_val)
                   | VVector arr ->
                       if Array.exists (function VString _ -> false | _ -> true) arr then
                         Error (Error.type_error "Function `populate_pipeline` expects `force` to contain only String values.")
                       else Ok (Some force_val)
                   | _ when force_provided ->
                       Error (Error.type_error "Function `populate_pipeline` expects `force` to be a Bool, String, List, or Vector.")
                   | _ -> Ok None
                 in
                 let dry_run_result =
                   match dry_run_val with
                   | VBool b -> Ok (Some b)
                   | _ when dry_run_provided ->
                       Error (Error.type_error "Function `populate_pipeline` expects `dry_run` to be a Bool.")
                   | _ -> Ok None
                 in
                 let max_jobs_result =
                   match max_jobs_val with
                   | VInt n when n > 0 -> Ok (Some max_jobs_val)
                   | _ when max_jobs_provided ->
                       Error (Error.type_error "Function `populate_pipeline` expects `max_jobs` to be a positive Int.")
                   | _ -> Ok None
                 in
                 let cache_result =
                   match cache_val with
                   | VString _ -> Ok (Some cache_val)
                   | _ when cache_provided ->
                       Error (Error.type_error "Function `populate_pipeline` expects `cache` to be a String.")
                   | _ -> Ok None
                 in
                 let builders_result =
                   match builders_val with
                   | VString _ -> Ok (Some builders_val)
                   | _ when builders_provided ->
                       Error (Error.type_error "Function `populate_pipeline` expects `builders` to be a String.")
                   | _ -> Ok None
                 in
                 let keep_env_result =
                   match keep_env_val with
                   | VString _ | VList _ | VVector _ ->
                       (match keep_env_val with
                        | VList items ->
                            if List.exists (function (_, VString _) -> false | _ -> true) items then
                              Error (Error.type_error "Function `populate_pipeline` expects `keep_env` to contain only String values.")
                            else Ok (Some keep_env_val)
                        | VVector arr ->
                            if Array.exists (function VString _ -> false | _ -> true) arr then
                              Error (Error.type_error "Function `populate_pipeline` expects `keep_env` to contain only String values.")
                            else Ok (Some keep_env_val)
                        | _ -> Ok (Some keep_env_val))
                   | _ when keep_env_provided ->
                       Error (Error.type_error "Function `populate_pipeline` expects `keep_env` to be a String, List, or Vector of strings.")
                   | _ -> Ok None
                 in
                 let sandbox_result =
                   match sandbox_val with
                   | VBool _ -> Ok (Some sandbox_val)
                   | VString s ->
                       if s = "relaxed" || s = "strict" || s = "none" then Ok (Some sandbox_val)
                       else Error (Error.value_error "Function `populate_pipeline` expects `sandbox` to be 'relaxed', 'strict', 'none', or a Bool.")
                   | _ when sandbox_provided ->
                       Error (Error.type_error "Function `populate_pipeline` expects `sandbox` to be a Bool or String.")
                   | _ -> Ok None
                 in

                 (match build_result, verbose_result, targets_result, force_result, dry_run_result, max_jobs_result, cache_result, builders_result, keep_env_result, sandbox_result with
                  | Error e, _, _, _, _, _, _, _, _, _
                  | _, Error e, _, _, _, _, _, _, _, _
                  | _, _, Error e, _, _, _, _, _, _, _
                  | _, _, _, Error e, _, _, _, _, _, _
                  | _, _, _, _, Error e, _, _, _, _, _
                  | _, _, _, _, _, Error e, _, _, _, _
                  | _, _, _, _, _, _, Error e, _, _, _
                  | _, _, _, _, _, _, _, Error e, _, _
                  | _, _, _, _, _, _, _, _, Error e, _
                  | _, _, _, _, _, _, _, _, _, Error e -> e
                  | Ok build, Ok verbose, Ok targets, Ok force, Ok dry_run, Ok max_jobs, Ok cache, Ok builders, Ok keep_env, Ok sandbox ->
                        match Builder.populate_pipeline ~build ?verbose ?targets ?force ?dry_run ?max_jobs ?cache ?builders ?keep_env ?sandbox p with
                        | Ok out ->
                            if build then (
                              let var_name =
                                match Env.fold (fun k val_v acc ->
                                  match val_v with
                                  | VPipeline p' when p'.p_exprs = p.p_exprs -> Some k
                                  | _ -> acc
                                ) env None with
                                | Some name -> name
                                | None -> "p"
                              in
                              let first_node =
                                match p.p_nodes with
                                | (name, _) :: _ -> name
                                | [] -> "my_node"
                              in
                              Printf.printf "\nPipeline successfully built!\n";
                              Printf.printf "  - Pipeline saved in variable '%s'\n" var_name;
                              Printf.printf "  - To read the contents of node '%s', use: read_node(%s.%s)\n" first_node var_name first_node;
                              Printf.printf "  - To inspect node metadata, use: inspect_node(%s.%s)\n" var_name first_node;
                              Printf.printf "  - To view pipeline summary, use: inspect_pipeline(%s)\n\n%!" var_name
                            );
                            out
                        | Error msg -> Error.make_error StructuralError msg))
      | _ ->
          Error.type_error "Function `populate_pipeline` expects a Pipeline."
  in
  Env.add "populate_pipeline" (make_builtin_named ~name:"populate_pipeline" ~variadic:true 1 populate_fn) env
