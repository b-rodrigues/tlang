open Ast

(*
--# Populate Pipeline
--#
--# Generates the `_pipeline/` directory with `pipeline.nix` and `dag.json`.
--# Optionally builds the pipeline.
--#
--# @name populate_pipeline
--# @param p :: Pipeline The pipeline to populate.
--# @param build :: Bool (Optional) Whether to trigger the Nix build immediately. Defaults to false.
--# @param verbose :: Int (Optional) Nix build verbosity level. `0` keeps build failures quiet; values above `0` print failed node logs.
--# @return :: String A status message or the output path if build=true.
--# @note `populate_pipeline` performs several validation checks before generating the Nix files:
--#   - **File Existence**: Verifies that all files specified in `functions` or `include` arguments of any node actually exist on the file system.
--#   - **Custom Function Warning**: Issues a warning to `stderr` if a node uses a custom `serializer` or `deserializer` but does not provide any companion `functions` files.
--#   - **Explicit Dependency Declaration**: Checks serializer/runtime requirements up front and asks to add missing entries to `tproject.toml` instead of injecting packages implicitly.
--# @family pipeline
--# @export
*)
let register env =
  let populate_fn named_args _env =
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
    match List.find_opt (fun k -> not (List.mem k ["p"; "build"; "verbose"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "populate_pipeline: unknown argument '%s'" k)
    | None when positional_count > 3 ->
        Error.make_error ArityError
          (Printf.sprintf "Function `populate_pipeline` accepts at most 3 positional arguments but received %d." positional_count)
    | None ->
      match get_arg "p" 1 (VNA NAGeneric) named_args with
      | (_, VPipeline p) ->
        let (build_provided, build_val) = get_arg "build" 2 (VBool false) named_args in
        let (verbose_provided, verbose_val) = get_arg "verbose" 3 (VNA NAGeneric) named_args in
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
        (match build_result, verbose_result with
         | Error e, _ -> e
         | _, Error e -> e
         | Ok build, Ok verbose ->
             let has_errors = List.exists (fun (_, v) -> is_error_value v) p.p_nodes in
             if has_errors then
               Error.value_error ("Cannot populate pipeline with errors: " ^ (Utils.value_to_string (VPipeline p)))
             else
               match Builder.populate_pipeline ~build ?verbose p with
               | Ok out -> VString out
               | Error msg -> Error.make_error FileError msg)
      | _ ->
          Error.type_error "Function `populate_pipeline` expects a Pipeline."
  in
  Env.add "populate_pipeline" (make_builtin_named ~name:"populate_pipeline" ~variadic:true 1 populate_fn) env
