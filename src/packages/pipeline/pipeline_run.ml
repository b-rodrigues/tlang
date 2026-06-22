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
--*)
let register ~(rerun_pipeline : ?strict:bool -> ?verbose:bool -> value Env.t -> pipeline_result -> value) env =
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
      match Pipeline_args.get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
        let (_, nix_options_val) = Pipeline_args.get_arg "nix_options" 2 (VDict []) named_args in

        let nix_options_result =
          match nix_options_val with
          | VNA _ -> Ok None
          | VDict pairs ->
              (match Builder_utils.validate_nix_options "pipeline_run" pairs with
               | Ok opts -> Ok (Some opts)
               | Error e -> Error e)
          | _ -> Error (Error.type_error "Function `pipeline_run` expects `nix_options` to be a Dictionary.")
        in

        (match nix_options_result with
         | Error e -> e
         | Ok nix_options ->
             (match rerun_pipeline ?strict:None env p with
              | VPipeline p_resolved ->
                  (match nix_options with
                   | Some opts when opts <> Builder_utils.default_nix_opts ->
                       (match Builder.populate_pipeline ~build:true ~nix_options:opts p_resolved with
                        | Ok (VDataFrame _ as df) -> df
                        | Ok (VString out_path) ->
                            VPipeline (Builder.update_pipeline_with_build_paths p_resolved out_path)
                        | Ok other -> other
                        | Error msg -> Error.make_error StructuralError msg)
                   | _ ->
                       VPipeline p_resolved)
              | VError _ as err -> err
              | other ->
                  Error.make_error RuntimeError
                    ("pipeline_run expected pipeline resolution to return a Pipeline or Error, but got: "
                     ^ Utils.value_to_string other)))
      | _ -> Error.type_error "Function `pipeline_run` expects a Pipeline."
  in
  Env.add "pipeline_run" (make_builtin_named ~name:"pipeline_run" ~variadic:true 1 run_fn) env
