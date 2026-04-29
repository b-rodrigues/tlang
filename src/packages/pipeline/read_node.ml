open Ast

(* 
--# Read Pipeline Node Artifact
--#
--# For in-memory Pipelines, returns a node record with the node value and
--# structured diagnostics. For built pipelines, reads the artifact from the
--# latest (or specified) build log in `_pipeline/`.
--# Use `which_log` to read from a specific historical build ("time travel").
--#
--# @name read_node
--# @param node :: Pipeline | String | ComputedNode Pass a Pipeline for in-memory node diagnostics, or a String/ComputedNode to load a built artifact.
--# @param name :: String (Optional) The node name to read when `node` is a Pipeline.
--# @param which_log :: String (Optional) A regex pattern to match a specific build log filename.
--# @return :: Any A Dict with value+diagnostics for in-memory pipelines, or the deserialized artifact for built nodes.
--# @family pipeline
--# @seealso read_pipeline, build_pipeline, inspect_pipeline
--# @export
*)
let register env =
  (* Helper to extract an argument from a named/positional list.
     @param name The name of the argument (for named calls).
     @param pos The 1-indexed position of the argument (for positional calls).
     @param default Fallback value if the argument is missing. *)
  let extract_arg name pos default args =
    match List.assoc_opt (Some name) args with
    | Some v -> v
    | None ->
        let positionals = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
        if List.length positionals >= pos then List.nth positionals (pos - 1)
        else default
  in

  let read_fn named_args _env =
    let read_computed_node_value cn =
      if cn.cn_runtime = "T" && (cn.cn_serializer = "default" || cn.cn_serializer = "serialize") then
        (match Serialization.deserialize_from_file cn.cn_path with
         | Ok v -> v
         | Error msg -> Error.make_error ~context:[("runtime", VString cn.cn_runtime)] FileError (Printf.sprintf "read_node: Failed to deserialize T node `%s`: %s" cn.cn_name msg))
      else if cn.cn_serializer = "json" then
        (match Serialization.read_json cn.cn_path with
         | Ok v -> v
         | Error msg -> Error.make_error ~context:[("runtime", VString cn.cn_runtime)] FileError (Printf.sprintf "read_node: Failed to read JSON node `%s`: %s" cn.cn_name msg))
      else if cn.cn_serializer = "arrow" then
        (match Arrow_io.read_ipc cn.cn_path with
         | Ok table -> VDataFrame { arrow_table = table; group_keys = [] }
         | Error msg -> Error.make_error ~context:[("runtime", VString cn.cn_runtime)] FileError (Printf.sprintf "read_node: Failed to read Arrow node `%s`: %s" cn.cn_name msg))
      else if cn.cn_serializer = "csv" then
        (try
           let ch = open_in cn.cn_path in
           let content = really_input_string ch (in_channel_length ch) in
           close_in ch;
           T_read_csv.parse_csv_string content
         with exn ->
           Error.make_error ~context:[("runtime", VString cn.cn_runtime)] FileError (Printf.sprintf "read_node: Failed to read CSV node `%s`: %s" cn.cn_name (Printexc.to_string exn)))
      else if cn.cn_serializer = "pmml" then
        (match Pmml_utils.read_pmml cn.cn_path with
         | Ok v -> Pmml_utils.attach_source_path cn.cn_path v
         | Error msg -> Error.make_error ~context:[("runtime", VString cn.cn_runtime)] FileError (Printf.sprintf "read_node: Failed to read PMML node `%s`: %s" cn.cn_name msg))
      else
        Error.make_error GenericError (Printf.sprintf "read_node: No automatic deserializer for runtime %s and serializer %s. Use a specific loader like read_csv(node.path)." cn.cn_runtime cn.cn_serializer)
    in
    let is_visual_metadata_class = function
      | "ggplot" | "matplotlib" | "plotnine" | "seaborn" | "plotly" | "altair" -> true
      | _ -> false
    in
    let uses_builtin_fallback_reader cn =
      (cn.cn_runtime = "T"
       && (cn.cn_serializer = "default" || cn.cn_serializer = "serialize"))
      || cn.cn_serializer = "json"
      || cn.cn_serializer = "arrow"
      || cn.cn_serializer = "csv"
      || cn.cn_serializer = "pmml"
    in
    match extract_arg "node" 1 ((VNA NAGeneric)) named_args with
    | VPipeline p ->
        let pipeline_diagnostics =
          Builder.merge_pipeline_node_diagnostics_with_latest_log p
        in
        (match extract_arg "name" 2 (VNA NAGeneric) named_args with
         | VString name ->
              (match List.assoc_opt name p.p_nodes with
               | Some value ->
                   let diagnostics =
                     match List.assoc_opt name pipeline_diagnostics with
                     | Some diagnostics -> diagnostics
                     | None -> Ast.Utils.empty_node_diagnostics
                   in
                  let warnings =
                    VList
                      (List.map
                         (fun warning -> (None, Ast.Utils.node_warning_to_value warning))
                         diagnostics.nd_warnings)
                  in
                  let error =
                    match diagnostics.nd_error with
                    | Some error -> Ast.Utils.node_error_to_value error
                    | None -> VNA NAGeneric
                  in
                  VDict [
                    ("name", VString name);
                    ("value", value);
                    ("warnings", warnings);
                    ("error", error);
                    ("diagnostics", Ast.Utils.node_diagnostics_to_value diagnostics);
                  ]
              | None ->
                  Error.make_error KeyError
                    (Printf.sprintf "Node `%s` not found in Pipeline." name))
         | VNA _ ->
             Error.make_error ValueError
               "read_node: when the first argument is a Pipeline, a node name is required as the second argument."
         | _ ->
             Error.type_error
               "read_node: expected a String node name as the second argument when reading from a Pipeline.")
    | VString name ->
        (match extract_arg "which_log" 2 (VNA NAGeneric) named_args with
         | VNA _ -> Builder.read_node name
         | VString s -> Builder.read_node ~which_log:s name
         | _ -> Error.type_error "read_node: expected String for 'which_log'")
     | VComputedNode cn ->
          if is_visual_metadata_class cn.cn_class then
            let viz_path = Filename.concat (Filename.dirname cn.cn_path) "viz" in
            if Sys.file_exists viz_path then
              (match Serialization.read_json viz_path with
               | Ok v -> v
               | Error msg -> Error.make_error ~context:[("runtime", VString cn.cn_runtime)] FileError (Printf.sprintf "read_node: Failed to read plot metadata node `%s`: %s" cn.cn_name msg))
            else
              read_computed_node_value cn
          else if uses_builtin_fallback_reader cn then
            read_computed_node_value cn
          else
            (match Serialization_registry.lookup cn.cn_serializer with
           | Some ser ->
                (match ser.s_reader with
                 | VBuiltin { b_func; _ } ->
                    b_func [(None, VString cn.cn_path)] (ref _env)
                 | _ ->
                     Error.make_error RuntimeError (Printf.sprintf "read_node: Serializer ^%s has no T-native reader." cn.cn_serializer))
            | None ->
                read_computed_node_value cn)
    | VNA _ -> Error.make_error ValueError "read_node: requires a node name or a ComputedNode object."
    | _ -> Error.type_error "read_node: expected String or ComputedNode for argument 'node'"
  in

(*
--# Read Pipeline Metadata
--#
--# Returns a dictionary describing a materialized in-memory pipeline,
--# including per-node diagnostics and the aggregated diagnostics summary.
--#
--# @name read_pipeline
--# @param p :: Pipeline The pipeline to inspect.
--# @return :: Dict A dictionary with node metadata and diagnostics.
--# @family pipeline
--# @seealso read_node, explain
--# @export
*)
  let read_pipeline_fn named_args _env =
    match extract_arg "p" 1 (VNA NAGeneric) named_args with
    | VPipeline p ->
        let pipeline_diagnostics =
          Builder.merge_pipeline_node_diagnostics_with_latest_log p
        in
        let nodes =
          VList
            (List.map (fun (name, value) ->
                let diagnostics =
                  match List.assoc_opt name pipeline_diagnostics with
                  | Some diagnostics -> diagnostics
                  | None -> Ast.Utils.empty_node_diagnostics
                in
               (None, VDict [
                 ("name", VString name);
                 ("value", value);
                 ("diagnostics", Ast.Utils.node_diagnostics_to_value diagnostics);
               ]))
              p.p_nodes)
        in
        VDict [
          ("nodes", nodes);
          ("diagnostics", Ast.Utils.pipeline_diagnostics_to_value pipeline_diagnostics);
        ]
    | _ -> Error.type_error "read_pipeline: expected a Pipeline."
  in

(*
--# Inspect Pipeline Node Metadata
--#
--# Returns a dictionary with metadata about a computed node, including its
--# name, runtime, artifact path, serializer, class, and dependencies.
--#
--# @name inspect_node
--# @param node :: ComputedNode A computed node value (e.g. from a built pipeline).
--# @return :: Dict A dictionary with keys = name, runtime, path, serializer, class, dependencies.
--# @family pipeline
--# @seealso read_node, rebuild_node
--# @export
*)
  let inspect_fn named_args _env =
    match extract_arg "node" 1 (VNA NAGeneric) named_args with
    | VComputedNode cn ->
        VDict [
          ("name", VString cn.cn_name);
          ("runtime", VString cn.cn_runtime);
          ("path", VString cn.cn_path);
          ("serializer", VString cn.cn_serializer);
          ("class", VString cn.cn_class);
          ("dependencies", VList (List.map (fun d -> (None, VString d)) cn.cn_dependencies))
        ]
    | _ -> Error.type_error "inspect_node: expected a ComputedNode."
  in

(*
--# Rebuild a Pipeline Node
--#
--# Rebuilds a single node from the pipeline Nix expression and returns an
--# updated ComputedNode with the new artifact path.
--#
--# @name rebuild_node
--# @param node :: ComputedNode A computed node value to rebuild.
--# @return :: ComputedNode An updated ComputedNode pointing to the rebuilt artifact.
--# @family pipeline
--# @seealso read_node, inspect_node
--# @export
*)
  let rebuild_fn named_args _env =
    match extract_arg "node" 1 (VNA NAGeneric) named_args with
    | VComputedNode cn ->
        let quoted_name = Filename.quote cn.cn_name in
        let cmd = Printf.sprintf "nix-build --impure _pipeline/pipeline.nix -A %s --no-out-link 2>&1" quoted_name in
        (match Builder_utils.run_command_capture cmd with
         | Ok (Unix.WEXITED 0, output) ->
             let store_path = String.trim output in
             let new_path = Filename.concat (Filename.concat store_path cn.cn_name) "artifact" in
             VComputedNode { cn with cn_path = new_path }
         | Ok (_, output) -> Error.make_error GenericError (Printf.sprintf "rebuild_node failed: %s" output)
         | Error msg -> Error.make_error GenericError (Printf.sprintf "Failed to run nix-build: %s" msg))
    | _ -> Error.type_error "rebuild_node: expected a ComputedNode."
  in

  let _ = 
    Ast.node_resolver := (fun name ->
      match Builder.read_node name with
      | VError _ -> None
      | v -> Some v)
  in

(*
--# Suppress Diagnostics for a Node
--#
--# Silences all captured warnings for the current node in the console summary.
--# Warnings remain accessible programmatically via `read_node()` or `read_pipeline()`.
--# Use this to reduce noise from known warnings during data processing (e.g., NAs in filter).
--#
--# @name suppress_warnings
--# @param value :: Any The value or expression to wrap. Usually call it at the end of a node definition.
--# @return :: Any The original value, signaling the evaluator to suppress diagnostic output.
--# @family pipeline
--# @export
*)
  let suppress_warnings_fn args _env =
    match args with
    | [VNodeResult nr] ->
        VNodeResult { nr with diagnostics = { nr.diagnostics with nd_warnings_suppressed = true } }
    | [v] -> 
        Eval.request_warning_suppression ();
        v
    | _ -> Error.arity_error_named "suppress_warnings" 1 (List.length args)
  in

  env
  |> Env.add "read_node" (make_builtin_named ~name:"read_node" ~variadic:true 1 read_fn)
  |> Env.add "read_pipeline" (make_builtin_named ~name:"read_pipeline" ~variadic:true 1 read_pipeline_fn)
  |> Env.add "inspect_node" (make_builtin_named ~name:"inspect_node" ~unwrap:false ~variadic:true 1 inspect_fn)
  |> Env.add "rebuild_node" (make_builtin_named ~name:"rebuild_node" ~unwrap:false ~variadic:true 1 rebuild_fn)
  |> Env.add "suppress_warnings" (make_builtin ~name:"suppress_warnings" ~unwrap:false 1 suppress_warnings_fn)
