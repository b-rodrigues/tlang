open Ast

(* 
--# Read Pipeline Node Artifact
--#
--# Reads and returns the contents of a ComputedNode. For in-memory pipelines,
--# returns the dynamically computed value directly from the registry. For built
--# pipelines, reads the materialized artifact from the latest (or specified) 
--# build log.
--# Use `which_log` to read from a specific historical build ("time travel").
--#
--# @name read_node
--# @param node :: ComputedNode The ComputedNode object to read (e.g. `p.node_name`).
--# @param which_log :: String (Optional) A regex pattern to match a specific build log filename.
--# @return :: Any The deserialized artifact value, or the in-memory value.
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

  let run_interactive_subshell cn =
    let cn = !Ast.computed_node_resolver cn in
    let dependencies =
      if cn.cn_dependencies = [] then
        (match Builder.latest_logged_computed_node cn.cn_name with
         | Some logged -> logged.cn_dependencies
         | None -> [])
      else cn.cn_dependencies
    in
    (* Set environment variables for all dependencies *)
    let dep_envs = ref [] in
    List.iter (fun dep_name ->
      match Builder.latest_logged_computed_node dep_name with
      | Some dep_cn ->
          if dep_cn.cn_path <> "" && dep_cn.cn_path <> "<unbuilt>" then (
            let store_dir = Filename.dirname dep_cn.cn_path in
            Unix.putenv dep_name store_dir;
            dep_envs := (dep_name, store_dir) :: !dep_envs
          ) else
            Printf.printf "Warning: Upstream dependency '%s' is not built yet; environment variable not set.\n%!" dep_name
      | None ->
          Printf.printf "Warning: Upstream dependency '%s' metadata not found; environment variable not set.\n%!" dep_name
    ) dependencies;

    Printf.printf "==================================================\n%!";
    Printf.printf "Debugging Node: %s (Runtime: %s)\n%!" cn.cn_name cn.cn_runtime;
    Printf.printf "==================================================\n%!";
    if !dep_envs <> [] then (
      Printf.printf "Environment variables set for dependencies:\n%!";
      List.iter (fun (name, path) ->
        Printf.printf "  - %s = %s\n%!" name path
      ) !dep_envs
    );
    Printf.printf "\n%!";

    let shell_cmd =
      let clean_deps = List.map (fun (name, _) -> name) !dep_envs in
      match String.lowercase_ascii cn.cn_runtime with
      | "python" ->
          Printf.printf "Starting interactive Python REPL...\n%!";
          Printf.printf "Tip: Load upstream dependencies in Python using:\n%!";
          Printf.printf "  import tlang\n%!";
          List.iter (fun dep ->
            Printf.printf "  %s = tlang.read_node(\"%s\")\n%!" dep dep
          ) clean_deps;
          if clean_deps = [] then
            Printf.printf "  # No upstream dependencies. You can import tlang: import tlang\n%!";
          "python -i"
      | "r" ->
          Printf.printf "Starting interactive R REPL...\n%!";
          Printf.printf "Tip: Load upstream dependencies in R using:\n%!";
          Printf.printf "  library(tlang)\n%!";
          List.iter (fun dep ->
            Printf.printf "  %s <- read_node(\"%s\")\n%!" dep dep
          ) clean_deps;
          if clean_deps = [] then
            Printf.printf "  # No upstream dependencies. You can load tlang: library(tlang)\n%!";
          "R --no-save"
      | "julia" ->
          Printf.printf "Starting interactive Julia REPL...\n%!";
          Printf.printf "Tip: Load upstream dependencies in Julia using:\n%!";
          Printf.printf "  using TLang\n%!";
          List.iter (fun dep ->
            Printf.printf "  %s = read_node(\"%s\")\n%!" dep dep
          ) clean_deps;
          if clean_deps = [] then
            Printf.printf "  # No upstream dependencies. You can load TLang: using TLang\n%!";
          "julia -i"
      | _ ->
          Printf.printf "Starting interactive bash subshell...\n%!";
          "bash"
    in
    Printf.printf "Press Ctrl+D or exit to return to T REPL.\n";
    Printf.printf "==================================================\n\n%!";
    flush stdout;
    let status = Unix.system shell_cmd in
    Printf.printf "\n==================================================\n%!";
    Printf.printf "Exited subshell (status: %s). Returning to T REPL.\n%!"
      (match status with
       | Unix.WEXITED n -> Printf.sprintf "exit %d" n
       | Unix.WSIGNALED n -> Printf.sprintf "signaled %d" n
       | Unix.WSTOPPED n -> Printf.sprintf "stopped %d" n);
    Printf.printf "==================================================\n%!";
    flush stdout;
    VNA NAGeneric
  in

  let debug_fn named_args _env =
    match extract_arg "node" 1 (VNA NAGeneric) named_args with
    | VComputedNode cn ->
        run_interactive_subshell cn
    | _ -> Error.type_error "debug_node: expected a ComputedNode."
  in

  let read_fn named_args _env =

    match extract_arg "node" 1 ((VNA NAGeneric)) named_args with
    | VComputedNode cn ->
        let which_log_provided =
          match extract_arg "which_log" 2 (VNA NAGeneric) named_args with
          | VString _ -> true
          | _ -> false
        in
        if not which_log_provided && Hashtbl.mem Ast.in_memory_node_values cn.cn_name then
          Hashtbl.find Ast.in_memory_node_values cn.cn_name
        else
          let cn_or_err =
            if which_log_provided then
              let log_name = match extract_arg "which_log" 2 (VNA NAGeneric) named_args with VString s -> s | _ -> "" in
              (match Builder.latest_logged_computed_node ~log_name_pattern:log_name cn.cn_name with
               | Some logged_cn ->
                   let cn_path = if cn.cn_path = "<unbuilt>" || cn.cn_path = "" then logged_cn.cn_path else cn.cn_path in
                   let cn_class = if cn.cn_class = "Unknown" then logged_cn.cn_class else cn.cn_class in
                   let cn_runtime = if cn.cn_runtime = "T" || cn.cn_runtime = "" then logged_cn.cn_runtime else cn.cn_runtime in
                   let cn_serializer = if cn.cn_serializer = "default" || cn.cn_serializer = "" then logged_cn.cn_serializer else cn.cn_serializer in
                   Ok { cn with cn_path; cn_class; cn_runtime; cn_serializer }
               | None ->
                   Error (Error.make_error KeyError (Printf.sprintf "Node `%s` not found in BuildLog." cn.cn_name)))
            else Ok (!Ast.computed_node_resolver cn)
          in
          (match cn_or_err with
           | Error err -> err
           | Ok cn ->
               if cn.cn_path = "<unbuilt>" && not which_log_provided then
                 (match Hashtbl.find_opt Ast.in_memory_node_values cn.cn_name with
                  | Some v -> v
                  | None ->
                      Error.make_error FileError (Printf.sprintf "read_node: Failed to deserialize T node `%s`: Sys_error(\"<unbuilt>: No such file or directory\")" cn.cn_name))
               else
                 let raw_val = Builder.logged_node_value cn.cn_name cn in
                 Builder.wrap_with_diagnostics cn.cn_name cn raw_val)
    | VString _ ->
        Error.type_error "read_node: expected a ComputedNode for argument 'node', but got String. Use read_node(p.node_name) instead."
    | VSymbol name as other ->
        let node_name =
          if String.length name > 6 && String.sub name 0 6 = "<noop:" then
            let len = String.length name in
            Some (String.sub name 6 (len - 7))
          else None
        in
        (match node_name with
         | Some real_name ->
             Error.type_error (Printf.sprintf "read_node: cannot read node `%s` because it was skipped (noop=true) or was a downstream dependency of a skipped node." real_name)
         | None ->
             Error.type_error (Printf.sprintf "read_node: expected a ComputedNode for argument 'node', but got %s." (Utils.type_name other)))
    | VPipeline _ ->
        Error.type_error "read_node: expected a ComputedNode for argument 'node', but got Pipeline. Use read_node(p.node_name) instead."
    | VNA _ -> Error.make_error ValueError "read_node: requires a ComputedNode object."
    | other ->
        Error.type_error (Printf.sprintf "read_node: expected a ComputedNode for argument 'node', but got %s." (Utils.type_name other))
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
        let pipeline_nodes =
          Builder.merge_pipeline_nodes_with_latest_log p
        in
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
              pipeline_nodes)
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
        let cn = !Ast.computed_node_resolver cn in
        VDict [
          ("name", VString cn.cn_name);
          ("runtime", VString cn.cn_runtime);
          ("path", VString cn.cn_path);
          ("serializer", VString cn.cn_serializer);
          ("class", VString cn.cn_class);
          ("dependencies", VList (List.map (fun d -> (None, VString d)) cn.cn_dependencies))
        ]
    | VError err ->
        let node_name =
          match List.assoc_opt "node_name" err.context with
          | Some (VString name) -> Some name
          | _ -> None
        in
        (match node_name with
         | Some name ->
             Error.type_error (Printf.sprintf "inspect_node: expected a ComputedNode, but got an Error because node `%s` failed. To inspect its error, query its properties (e.g. `node.error_msg` or `node.error`) or use `read_node(p, \"%s\")`." name name)
         | None ->
             Error.type_error "inspect_node: expected a ComputedNode, but got an Error value. If this is a failing pipeline node, use its error properties or read_node() to inspect it.")
    | VSymbol name as other ->
        let node_name =
          if String.length name > 6 && String.sub name 0 6 = "<noop:" then
            let len = String.length name in
            Some (String.sub name 6 (len - 7))
          else None
        in
        (match node_name with
         | Some real_name ->
             Error.type_error (Printf.sprintf "inspect_node: expected a ComputedNode, but node `%s` was skipped (noop=true) or was a downstream dependency of a skipped node, so no output was generated." real_name)
         | None ->
             Error.type_error (Printf.sprintf "inspect_node: expected a ComputedNode, but got %s." (Utils.type_name other)))
    | other ->
        Error.type_error (Printf.sprintf "inspect_node: expected a ComputedNode, but got %s." (Utils.type_name other))
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
      | v -> Some v);
    Ast.computed_node_resolver := (fun cn ->
      match Builder.latest_logged_computed_node cn.cn_name with
      | Some logged_cn ->
          let cn_class =
            if cn.cn_class = "Unknown" || cn.cn_class = "" then logged_cn.cn_class else cn.cn_class
          in
          let cn_path =
            if logged_cn.cn_path = "" then ""
            else if cn.cn_path = "<unbuilt>" || cn.cn_path = ""
            then logged_cn.cn_path
            else cn.cn_path
          in
          let cn_runtime =
            if cn.cn_runtime = "T" || cn.cn_runtime = ""
            then logged_cn.cn_runtime
            else cn.cn_runtime
          in
          let cn_serializer =
            if cn.cn_serializer = "default" || cn.cn_serializer = ""
            then logged_cn.cn_serializer
            else cn.cn_serializer
          in
          { cn with cn_path; cn_class; cn_runtime; cn_serializer }
      | None -> cn)
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
  |> Env.add "debug_node" (make_builtin_named ~name:"debug_node" ~unwrap:false ~variadic:true 1 debug_fn)
