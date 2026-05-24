open Ast

(*
--# Run Pipeline
--#
--# Re-executes a pipeline from start to finish. When any Nix orchestration
--# argument is supplied, delegates to a Nix build instead of in-memory re-eval.
--#
--# @name pipeline_run
--# @param p :: Pipeline The pipeline to run.
--# @param nix_options :: Dict (Optional) A dictionary of Nix orchestration options:
--#   - `targets` :: List[String] Specific node names to build. Maps to `-A <target>` in nix-build.
--#   - `force` :: Bool|List[String] Force-rebuild nodes even if cached. Maps to `--check`.
--#   - `dry_run` :: Bool Return a planned build DataFrame without executing. Maps to `--dry-run`.
--#   - `max_jobs` :: Int Maximum parallel build jobs. Maps to `--max-jobs N`.
--#   - `cache` :: String Cachix cache name to configure as an extra binary substituter.
--# @return :: Pipeline|DataFrame The executed pipeline, or a dry-run plan DataFrame.
--# @family pipeline
--# @seealso pipeline_nodes
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
  let run_fn named_args env =
    let named_keys = List.filter_map (fun (k, _) -> k) named_args in
    let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
    match List.find_opt (fun k -> not (List.mem k ["p"; "nix_options"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "pipeline_run: unknown argument '%s'" k)
    | None when positional_count > 2 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `pipeline_run` accepts at most 2 positional arguments but received %d." positional_count)
    | None ->
      match get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
        let (_, nix_options_val) = get_arg "nix_options" 2 (VDict []) named_args in

        let nix_options_result =
          match nix_options_val with
          | VNA _ -> Ok []
          | VDict pairs -> Ok pairs
          | _ -> Error (Error.type_error "Function `pipeline_run` expects `nix_options` to be a Dictionary.")
        in

        (match nix_options_result with
         | Error e -> e
         | Ok pairs ->
             match List.find_opt (fun (k, _) -> not (List.mem k ["targets"; "force"; "dry_run"; "max_jobs"; "cache"; "builders"; "keep_env"; "sandbox"])) pairs with
             | Some (k, _) ->
                 Error.type_error (Printf.sprintf "pipeline_run: unknown option '%s' in nix_options" k)
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

                 let targets_result =
                   match targets_val with
                   | VString _ -> Ok (Some targets_val)
                   | VList items ->
                       if List.exists (function (_, VString _) -> false | _ -> true) items then
                         Error (Error.type_error "Function `pipeline_run` expects `targets` to contain only String values.")
                       else Ok (Some targets_val)
                   | VVector arr ->
                       if Array.exists (function VString _ -> false | _ -> true) arr then
                         Error (Error.type_error "Function `pipeline_run` expects `targets` to contain only String values.")
                       else Ok (Some targets_val)
                   | _ when targets_provided ->
                       Error (Error.type_error "Function `pipeline_run` expects `targets` to be a String, List, or Vector.")
                   | _ -> Ok None
                 in
                 let force_result =
                   match force_val with
                   | VBool _ | VList _ | VVector _ | VString _ -> Ok (Some force_val)
                   | _ when force_provided ->
                       Error (Error.type_error "Function `pipeline_run` expects `force` to be a Bool, String, List, or Vector.")
                   | _ -> Ok None
                 in
                 let dry_run_result =
                   match dry_run_val with
                   | VBool b -> Ok (Some b)
                   | _ when dry_run_provided ->
                       Error (Error.type_error "Function `pipeline_run` expects `dry_run` to be a Bool.")
                   | _ -> Ok None
                 in
                 let max_jobs_result =
                   match max_jobs_val with
                   | VInt n when n > 0 -> Ok (Some max_jobs_val)
                   | _ when max_jobs_provided ->
                       Error (Error.type_error "Function `pipeline_run` expects `max_jobs` to be a positive Int.")
                   | _ -> Ok None
                 in
                 let cache_result =
                   match cache_val with
                   | VString _ -> Ok (Some cache_val)
                   | _ when cache_provided ->
                       Error (Error.type_error "Function `pipeline_run` expects `cache` to be a String.")
                   | _ -> Ok None
                 in
                 let builders_result =
                   match builders_val with
                   | VString _ -> Ok (Some builders_val)
                   | _ when builders_provided ->
                       Error (Error.type_error "Function `pipeline_run` expects `builders` to be a String.")
                   | _ -> Ok None
                 in
                 let keep_env_result =
                   match keep_env_val with
                   | VString _ | VList _ | VVector _ ->
                       (match keep_env_val with
                        | VList items ->
                            if List.exists (function (_, VString _) -> false | _ -> true) items then
                              Error (Error.type_error "Function `pipeline_run` expects `keep_env` to contain only String values.")
                            else Ok (Some keep_env_val)
                        | VVector arr ->
                            if Array.exists (function VString _ -> false | _ -> true) arr then
                              Error (Error.type_error "Function `pipeline_run` expects `keep_env` to contain only String values.")
                            else Ok (Some keep_env_val)
                        | _ -> Ok (Some keep_env_val))
                   | _ when keep_env_provided ->
                       Error (Error.type_error "Function `pipeline_run` expects `keep_env` to be a String, List, or Vector of strings.")
                   | _ -> Ok None
                 in
                 let sandbox_result =
                   match sandbox_val with
                   | VBool _ -> Ok (Some sandbox_val)
                   | VString s ->
                       if s = "relaxed" || s = "strict" || s = "none" then Ok (Some sandbox_val)
                       else Error (Error.value_error "Function `pipeline_run` expects `sandbox` to be 'relaxed', 'strict', 'none', or a Bool.")
                   | _ when sandbox_provided ->
                       Error (Error.type_error "Function `pipeline_run` expects `sandbox` to be a Bool or String.")
                   | _ -> Ok None
                 in

                 (match targets_result, force_result, dry_run_result, max_jobs_result, cache_result, builders_result, keep_env_result, sandbox_result with
                  | Error e, _, _, _, _, _, _, _
                  | _, Error e, _, _, _, _, _, _
                  | _, _, Error e, _, _, _, _, _
                  | _, _, _, Error e, _, _, _, _
                  | _, _, _, _, Error e, _, _, _
                  | _, _, _, _, _, Error e, _, _
                  | _, _, _, _, _, _, Error e, _
                  | _, _, _, _, _, _, _, Error e -> e
                  | Ok targets, Ok force, Ok dry_run, Ok max_jobs, Ok cache, Ok builders, Ok keep_env, Ok sandbox ->
                      (match rerun_pipeline ?strict:None env p with
                       | VPipeline p_resolved ->
                           if targets_provided || force_provided || dry_run_provided || max_jobs_provided || cache_provided || builders_provided || keep_env_provided || sandbox_provided then
                             (match Builder.populate_pipeline ~build:true ?targets ?force ?dry_run ?max_jobs ?cache ?builders ?keep_env ?sandbox p_resolved with
                              | Ok (VDataFrame _ as df) -> df
                              | Ok (VString out_path) ->
                                  VPipeline (Builder.update_pipeline_with_build_paths p_resolved out_path)
                              | Ok other -> other
                              | Error msg -> Error.make_error StructuralError msg)
                           else
                             VPipeline p_resolved
                       | VError _ as err -> err
                       | other ->
                           Error.make_error RuntimeError
                             ("pipeline_run expected pipeline resolution to return a Pipeline or Error, but got: "
                              ^ Utils.value_to_string other))))
      | _ -> Error.type_error "Function `pipeline_run` expects a Pipeline."
  in
  Env.add "pipeline_run" (make_builtin_named ~name:"pipeline_run" ~variadic:true 1 run_fn) env
