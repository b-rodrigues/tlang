open Ast

(*
--# Build Pipeline Artifacts
--#
--# Builds a pipeline to `pipeline.nix` and records node artifacts in a local registry.
--#
--# @name build_pipeline
--# @param p :: Pipeline The pipeline to build.
--# @param verbose :: Int (Optional) Nix build verbosity level. `0` keeps build failures quiet; values above `0` print failed node logs.
--# @return :: String The output path (Nix store path or local fallback directory).
--# @family pipeline
--# @seealso read_node
--# @export
*)
let register ~rerun_pipeline env =
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
    match List.find_opt (fun k -> not (List.mem k ["p"; "verbose"])) named_keys with
    | Some k ->
        Error.type_error (Printf.sprintf "build_pipeline: unknown argument '%s'" k)
    | None when positional_count > 2 ->
        Error.arity_error_named "build_pipeline" 2 positional_count
    | None ->
      match get_arg "p" 1 VNull named_args with
      | (_, VPipeline p) ->
        let (verbose_provided, verbose_val) = get_arg "verbose" 2 VNull named_args in
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
        (match verbose_result with
         | Error e -> e
         | Ok verbose ->
             (* Trigger a final resolution pass to catch typos or unresolved cross-pipeline deps *)
             (match rerun_pipeline ?strict:(Some true) env p with
              | VPipeline p_resolved ->
                  let has_errors = List.exists (fun (_, v) -> is_error_value v) p_resolved.p_nodes in
                  if has_errors then
                    Error.value_error ("Cannot build pipeline with errors: " ^ (Utils.value_to_string (VPipeline p_resolved)))
                  else
                    (match Builder.populate_pipeline ~build:true ?verbose p_resolved with
                     | Ok out_path -> VString out_path
                     | Error msg -> Error.make_error FileError msg)
              | VError _ as err -> err
              | other ->
                  Error.make_error RuntimeError
                    ("build_pipeline expected pipeline resolution to return a Pipeline or Error before building, but got: "
                     ^ Utils.value_to_string other)))
      | _ -> Error.type_error "Function `build_pipeline` expects a Pipeline."
  in
  Env.add "build_pipeline" (make_builtin_named ~name:"build_pipeline" ~variadic:true 1 build_fn) env
