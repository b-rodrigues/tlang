open Ast

(*
--# Get Pipeline Node Options (read-back)
--#
--# Returns a Dict describing the fully resolved configuration of a single
--# pipeline node, after any `set_pipeline_global_options` merges have been
--# applied.  This is the read-back companion to
--# `set_pipeline_global_options`: what you merged in, you can read back out.
--#
--# The returned Dict has the following keys:
--# - `name` — the node name (String)
--# - `runtime` — one of "T", "R", "Python", "Julia", "Quarto", "sh" (String)
--# - `serializer` — e.g. "default", "pmml" (String)
--# - `deserializer` — e.g. "default", "pmml" (String)
--# - `noop` — whether the node is a no-op (Bool)
--# - `deps` — names of nodes this node depends on (List of String)
--# - `depth` — topological depth in the DAG (Int); roots are depth 0
--# - `command_type` — one of "command" or "script" (String)
--# - `diagnostics` — node diagnostics (Dict)
--# - `functions` — function files merged into the node (List of String)
--# - `include` — included files (List of String)
--# - `env_vars` — build environment variables (Dict)
--# - `args` — runtime/tool arguments (Dict)
--# - `shell` — shell interpreter, or NA when unset (String | NA)
--# - `shell_args` — shell interpreter arguments (List of String)
--# - `flake` — Nix flake path, or NA when unset (String | NA)
--#
--# An unknown node name is a `TypeError` listing the valid node names.
--#
--# @name pipeline_node_options
--# @param pipeline :: Pipeline The input pipeline.
--# @param node :: String The node name to read back.
--# @return :: Dict The resolved node configuration.
--# @family pipeline
--# @seealso set_pipeline_global_options, pipeline_to_frame
--# @export
--# @example
--#   pipeline_node_options(p, "n1")
--*)

let register env =
  Env.add "pipeline_node_options"
    (make_builtin_named ~name:"pipeline_node_options" 2 (fun args _env ->
      match args with
      | [None, VPipeline p; None, (VString name | VSymbol name)] ->
          let node_names = List.map fst p.p_exprs in
          if not (List.mem name node_names) then
            Error.type_error (Printf.sprintf
              "pipeline_node_options: unknown node `%s`. Valid node names are: %s."
              name
              (String.concat ", " (List.map (fun s -> "`" ^ s ^ "`") node_names)))
          else
            let depths = Pipeline_to_frame.compute_depths p.p_deps in
            let base = Pipeline_to_frame.node_metadata_dict name p depths in
            let expr_to_value e =
              match e.node with
              | Value v -> v
              | Var v -> VString v
              | _ -> VNA NAGeneric
            in
            let expr_list_to_value lst =
              VList (List.map (fun e -> (None, expr_to_value e)) lst)
            in
            let funcs = match List.assoc_opt name p.p_functions with
              | Some f -> expr_list_to_value f | None -> VList [] in
            let incs = match List.assoc_opt name p.p_includes with
              | Some f -> expr_list_to_value f | None -> VList [] in
            let env_vars = match List.assoc_opt name p.p_env_vars with
              | Some pairs -> VDict pairs | None -> VDict [] in
            let rt_args = match List.assoc_opt name p.p_args with
              | Some pairs -> VDict pairs | None -> VDict [] in
            let shell = match List.assoc_opt name p.p_shells with
              | Some (Some s) -> VString s | _ -> VNA NAGeneric in
            let shell_args = match List.assoc_opt name p.p_shell_args with
              | Some f -> expr_list_to_value f | None -> VList [] in
            let flake = match List.assoc_opt name p.p_flakes with
              | Some (Some f) -> VString f | _ -> VNA NAGeneric in
            VDict (base @ [
              ("functions",  funcs);
              ("include",    incs);
              ("env_vars",   env_vars);
              ("args",       rt_args);
              ("shell",      shell);
              ("shell_args", shell_args);
              ("flake",      flake);
            ])
      | [None, VPipeline _; None, other] ->
          Error.type_error (Printf.sprintf "pipeline_node_options: expected a String node name, got %s." (Utils.type_name other))
      | [None, VPipeline _; Some n, _] ->
          Error.type_error (Printf.sprintf "pipeline_node_options: node must be passed positionally, but got named argument `%s`." n)
      | [None, other; _] ->
          Error.type_error (Printf.sprintf "pipeline_node_options: expected a pipeline, got %s." (Utils.type_name other))
      | _ ->
          Error.arity_error_named "pipeline_node_options" 2 (List.length args)))
    env
