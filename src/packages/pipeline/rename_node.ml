open Ast

(*
--# Rename a Pipeline Node
--#
--# Renames a single node and rewires all dependency edges that referenced the
--# old name to the new name. This is the canonical way to resolve name
--# collisions before set operations.
--#
--# @name rename_node
--# @param p :: Pipeline The pipeline.
--# @param old_name :: String The current name of the node.
--# @param new_name :: String The desired new name.
--# @return :: Pipeline A new pipeline with the node renamed.
--# @example
--#   p |> rename_node("model_r", "model_r_v2")
--# @family pipeline
--# @seealso mutate_node, filter_node
--# @export
*)
let register env =
  Env.add "rename_node"
    (make_builtin ~name:"rename_node" 3 (fun args _env ->
      match args with
      | [VPipeline p; VString old_name; VString new_name] ->
          if not (List.mem_assoc old_name p.p_exprs) then
            Error.make_error KeyError
              (Printf.sprintf "Node `%s` not found in Pipeline." old_name)
          else if List.mem_assoc new_name p.p_exprs then
            Error.make_error ValueError
              (Printf.sprintf "A node named `%s` already exists in the Pipeline." new_name)
          else
            (* Helper: rename a key in an association list *)
            let rename_key lst =
              List.map (fun (k, v) -> if k = old_name then (new_name, v) else (k, v)) lst
            in
            (* Helper: replace old_name with new_name inside dependency lists *)
            let rewire_deps lst =
              List.map (fun (k, deps) ->
                (k, List.map (fun d -> if d = old_name then new_name else d) deps)
              ) lst
            in
            VPipeline {
              p_nodes        = rename_key p.p_nodes;
              p_exprs        = rename_key p.p_exprs;
              p_deps         = rewire_deps (rename_key p.p_deps);
              p_imports      = p.p_imports;
              p_runtimes     = rename_key p.p_runtimes;
              p_serializers  = rename_key p.p_serializers;
              p_deserializers = rename_key p.p_deserializers;
              p_env_vars     = rename_key p.p_env_vars;
              p_args         = rename_key p.p_args; p_shells       = rename_key p.p_shells; p_shell_args   = rename_key p.p_shell_args;
              p_functions    = rename_key p.p_functions;
              p_includes     = rename_key p.p_includes;
              p_noops        = rename_key p.p_noops;
              p_scripts      = rename_key p.p_scripts;
            }
      | [VPipeline _; VString _; _] ->
          Error.type_error "Function `rename_node` expects String arguments for old and new names."
      | [VPipeline _; _; _] ->
          Error.type_error "Function `rename_node` expects String arguments for old and new names."
      | [_; _; _] ->
          Error.type_error "Function `rename_node` expects a Pipeline as first argument."
      | _ -> Error.arity_error_named "rename_node" ~expected:3 ~received:(List.length args)
    ))
    env
