open Ast

(*
--# Filter Pipeline Nodes
--#
--# Returns a new pipeline containing only the nodes for which the predicate
--# returns `true`. Uses NSE (`$field`) to refer to node metadata fields.
--#
--# No DAG validity check is performed. If a retained node depends on a node
--# that was removed, that inconsistency surfaces only at `build_pipeline` or
--# `pipeline_run`.
--#
--# Supported metadata fields: `$name`, `$runtime`, `$serializer`,
--# `$deserializer`, `$noop`, `$depth`, `$command_type`.
--#
--# @name filter_node
--# @param p :: Pipeline The pipeline to filter.
--# @param predicate :: Function A predicate function returning Bool for each node.
--# @return :: Pipeline A new pipeline with only the matching nodes.
--# @example
--#   p |> filter_node($runtime == "python")
--#   p |> filter_node($noop == false)
--#   p |> filter_node($depth <= 2)
--# @family pipeline
--# @seealso mutate_node, select_node, rename_node
--# @export
*)
let register ~eval_call env =
  Env.add "filter_node"
    (make_builtin ~name:"filter_node" 2 (fun args env ->
      match args with
      | [VPipeline p; predicate] ->
          let depths = Pipeline_to_frame.compute_depths p.p_deps in
          let keep = List.filter (fun (name, _) ->
            let row_dict = VDict (Pipeline_to_frame.node_metadata_dict name p depths) in
            match eval_call env predicate [(None, Value row_dict)] with
            | VBool b -> b
            | _ -> false
          ) p.p_exprs in
          let keep_names = List.map fst keep in
          let keep_set name = List.mem name keep_names in
          VPipeline {
            p_nodes        = List.filter (fun (n, _) -> keep_set n) p.p_nodes;
            p_exprs        = keep;
            p_deps         = List.filter (fun (n, _) -> keep_set n) p.p_deps;
             p_imports      = p.p_imports;
             p_runtimes     = List.filter (fun (n, _) -> keep_set n) p.p_runtimes;
             p_serializers  = List.filter (fun (n, _) -> keep_set n) p.p_serializers;
             p_deserializers = List.filter (fun (n, _) -> keep_set n) p.p_deserializers;
             p_env_vars     = List.filter (fun (n, _) -> keep_set n) p.p_env_vars;
             p_functions    = List.filter (fun (n, _) -> keep_set n) p.p_functions;
             p_includes     = List.filter (fun (n, _) -> keep_set n) p.p_includes;
             p_noops        = List.filter (fun (n, _) -> keep_set n) p.p_noops;
             p_scripts      = List.filter (fun (n, _) -> keep_set n) p.p_scripts;
          }
      | [_; _] -> Error.type_error "Function `filter_node` expects a Pipeline as first argument."
      | _ -> Error.arity_error_named "filter_node" ~expected:2 ~received:(List.length args)
    ))
    env
