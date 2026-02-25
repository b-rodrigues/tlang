open Ast

(*
--# Read Pipeline Node Artifact
--#
--# Reads a node artifact from the latest (or specified) build log in `_pipeline/`.
--# Use `which_log` to read from a specific historical build ("time travel").
--#
--# @name read_node
--# @param name :: String The node name.
--# @param which_log :: String (Optional) A regex pattern to match a specific build log filename.
--# @return :: Any The deserialized value.
--# @family pipeline
--# @seealso build_pipeline, inspect_pipeline
--# @export
*)
let register env =
  let get_arg name pos default named_args =
    match List.assoc_opt name (List.filter_map (fun (k, v) -> match k with Some s -> Some (s, v) | None -> None) named_args) with
    | Some v -> v
    | None ->
        let positionals = List.filter_map (fun (k, v) -> match k with None -> Some v | Some _ -> None) named_args in
        if List.length positionals >= pos then List.nth positionals (pos - 1)
        else default
  in

  let read_fn named_args _env =
    match get_arg "node" 1 (VNull) named_args with
    | VString name ->
        (match get_arg "which_log" 2 VNull named_args with
         | VNull -> Builder.read_node name
         | VString s -> Builder.read_node ~which_log:s name
         | _ -> Error.type_error "read_node: expected String for 'which_log'")
    | VComputedNode cn ->
        if cn.cn_runtime = "T" && (cn.cn_serializer = "default" || cn.cn_serializer = "serialize") then
          (match Serialization.deserialize_from_file cn.cn_path with
           | Ok v -> v
           | Error msg -> Error.make_error FileError (Printf.sprintf "read_node: Failed to deserialize T node `%s`: %s" cn.cn_name msg))
        else if cn.cn_serializer = "json" then
          (match Serialization.read_json cn.cn_path with
           | Ok v -> v
           | Error msg -> Error.make_error FileError (Printf.sprintf "read_node: Failed to read JSON node `%s`: %s" cn.cn_name msg))
        else if cn.cn_serializer = "arrow" then
          (match Arrow_io.read_ipc cn.cn_path with
           | Ok table -> VDataFrame { arrow_table = table; group_keys = [] }
           | Error msg -> Error.make_error FileError (Printf.sprintf "read_node: Failed to read Arrow node `%s`: %s" cn.cn_name msg))
        else
          Error.make_error GenericError (Printf.sprintf "read_node: No automatic deserializer for runtime %s and serializer %s. Use a specific loader like read_csv(node.path)." cn.cn_runtime cn.cn_serializer)
    | VNull -> Error.make_error ValueError "read_node: requires a node name or a ComputedNode object."
    | _ -> Error.type_error "read_node: expected String or ComputedNode for argument 'node'"
  in

(*
--# Inspect Pipeline Node Metadata
--#
--# Returns a dictionary with metadata about a computed node, including its
--# name, runtime, artifact path, serializer, class, and dependencies.
--#
--# @name inspect_node
--# @param node :: ComputedNode A computed node value (e.g. from a built pipeline).
--# @return :: Dict A dictionary with keys: name, runtime, path, serializer, class, dependencies.
--# @family pipeline
--# @seealso read_node, rebuild_node
--# @export
*)
  let inspect_fn named_args _env =
    match get_arg "node" 1 VNull named_args with
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
    match get_arg "node" 1 VNull named_args with
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
  env
  |> Env.add "read_node" (make_builtin_named ~name:"read_node" ~variadic:true 1 read_fn)
  |> Env.add "inspect_node" (make_builtin_named ~name:"inspect_node" ~variadic:true 1 inspect_fn)
  |> Env.add "rebuild_node" (make_builtin_named ~name:"rebuild_node" ~variadic:true 1 rebuild_fn)
