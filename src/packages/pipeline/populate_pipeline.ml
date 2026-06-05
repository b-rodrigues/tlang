open Ast
open Pipeline_utils

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
--# @param dry_run :: Bool (Optional) Perform a dry run via Nix (`--dry-run`), returning a DataFrame of planned actions without executing.
--# @param nix_options :: Dict (Optional) A dictionary of Nix orchestration options:
--#   - `targets` :: List[String] Specific node names to build. Maps to `-A <target>` in nix-build.
--#   - `force` :: Bool|List[String] Force-rebuild nodes even if cached. Maps to `--check`.
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
          match nth_safe (pos - 1) positionals with
          | Some v -> (true, v)
          | None -> (false, default)
    in
    let named_keys = List.filter_map (fun (k, _) -> k) named_args in
    let positional_count = List.length (List.filter (fun (k, _) -> k = None) named_args) in
    match List.find_opt (fun k -> not (List.mem k ["p"; "build"; "verbose"; "nix_options"; "dry_run"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "populate_pipeline: unknown argument '%s'" k)
    | None when positional_count > 5 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `populate_pipeline` accepts at most 5 positional arguments but received %d." positional_count)
    | None ->
      match get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
        let (build_provided, build_val) = get_arg "build" 2 (VBool false) named_args in
        let (verbose_provided, verbose_val) = get_arg "verbose" 3 (VNA NAGeneric) named_args in
        let (_, nix_options_val) = get_arg "nix_options" 4 (VDict []) named_args in
        let (dry_run_provided, dry_run_val) = get_arg "dry_run" 5 (VNA NAGeneric) named_args in

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
        let nix_options_result =
          match nix_options_val with
          | VNA _ -> Ok None
          | VDict pairs ->
              (match Builder_utils.validate_nix_options "populate_pipeline" pairs with
               | Ok opts -> Ok (Some opts)
               | Error e -> Error e)
          | _ -> Error (Error.type_error "Function `populate_pipeline` expects `nix_options` to be a Dictionary.")
        in
        let dry_run_result =
          match dry_run_val with
          | VBool b -> Ok (Some b)
          | VNA _ -> Ok None
          | _ when dry_run_provided ->
              Error (Error.type_error "Function `populate_pipeline` expects `dry_run` to be a Bool.")
          | _ -> Ok None
        in

        (match build_result, verbose_result, nix_options_result, dry_run_result with
         | Error e, _, _, _ | _, Error e, _, _ | _, _, Error e, _ | _, _, _, Error e -> e
         | Ok build, Ok verbose, Ok nix_options, Ok dry_opt ->
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
             let final_build =
               match final_nix_options with
               | Some opts ->
                   (match opts.dry_run with
                    | Some true -> true
                    | _ -> build)
               | None -> build
             in
             (match Builder.populate_pipeline ~build:final_build ?verbose ?nix_options:final_nix_options p with
              | Ok out ->
                  if final_build && (match final_nix_options with Some opts -> opts.dry_run <> Some true | None -> true) then (
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
