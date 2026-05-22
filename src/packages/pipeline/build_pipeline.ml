open Ast

(*
--# Build Pipeline Artifacts
--#
--# Builds a pipeline to `pipeline.nix` and records node artifacts in a local registry.
--# Supports Nix-native orchestration flags for targeted builds, cache usage, and dry-runs.
--#
--# @name build_pipeline
--# @param p :: Pipeline The pipeline to build.
--# @param verbose :: Int (Optional) Nix build verbosity level. `0` keeps build failures quiet; values above `0` print failed node logs.
--# @param targets :: List[String] (Optional) Specific node names to build. Maps to `-A <target>` in nix-build.
--# @param force :: Bool|List[String] (Optional) Force-rebuild nodes even if cached. Maps to `--check`.
--# @param dry_run :: Bool (Optional) Return a planned build DataFrame without executing. Maps to `--dry-run`.
--# @param max_jobs :: Int (Optional) Maximum parallel build jobs. Maps to `--max-jobs N`.
--# @param cache :: String (Optional) Cachix cache name to configure as an extra binary substituter.
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
    match List.find_opt (fun k -> not (List.mem k ["p"; "verbose"; "targets"; "force"; "dry_run"; "max_jobs"; "cache"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "build_pipeline: unknown argument '%s'" k)
    | None when positional_count > 2 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `build_pipeline` accepts at most 2 positional arguments but received %d." positional_count)
    | None ->
      match get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
        let (verbose_provided, verbose_val) = get_arg "verbose" 2 (VNA NAGeneric) named_args in
        let (targets_provided, targets_val) = get_arg "targets" 3 (VNA NAGeneric) named_args in
        let (force_provided, force_val) = get_arg "force" 4 (VNA NAGeneric) named_args in
        let (dry_run_provided, dry_run_val) = get_arg "dry_run" 5 (VNA NAGeneric) named_args in
        let (max_jobs_provided, max_jobs_val) = get_arg "max_jobs" 6 (VNA NAGeneric) named_args in
        let (cache_provided, cache_val) = get_arg "cache" 7 (VNA NAGeneric) named_args in

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
        (match verbose_result, targets_result, force_result, dry_run_result, max_jobs_result, cache_result with
         | Error e, _, _, _, _, _
         | _, Error e, _, _, _, _
         | _, _, Error e, _, _, _
         | _, _, _, Error e, _, _
         | _, _, _, _, Error e, _
         | _, _, _, _, _, Error e -> e
         | Ok verbose, Ok targets, Ok force, Ok dry_run, Ok max_jobs, Ok cache ->
             (* Trigger a final resolution pass to catch typos or unresolved cross-pipeline deps *)
             (match rerun_pipeline ?strict:(Some true) ~verbose:false env p with
              | VPipeline p_resolved ->
                   (match Builder.populate_pipeline ~build:true ?verbose ?targets ?force ?dry_run ?max_jobs ?cache p_resolved with
                    | Ok (VDataFrame _ as df) -> df
                    | Ok (VString out_path) ->
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
                     ^ Utils.value_to_string other)))
      | _ -> Error.type_error "Function `build_pipeline` expects a Pipeline."
  in
  Env.add "build_pipeline" (make_builtin_named ~name:"build_pipeline" ~variadic:true 1 build_fn) env
