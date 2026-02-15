open Ast

(*
--# Get Pipeline Node
--#
--# Retrieves the value of a specific node in the pipeline.
--#
--# @name pipeline_node
--# @param p :: Pipeline The pipeline.
--# @param name :: String The node name.
--# @return :: Any The value of the node.
--# @family pipeline
--# @seealso pipeline_nodes
--# @export
*)
let register env =
  Env.add "pipeline_node"
    (make_builtin 2 (fun args _env ->
      match args with
      | [VPipeline { p_nodes; _ }; VString name] ->
          (match List.assoc_opt name p_nodes with
           | Some v -> v
           | None -> Error.make_error KeyError (Printf.sprintf "Node `%s` not found in Pipeline." name))
      | [VPipeline _; _] -> Error.type_error "Function `pipeline_node` expects a String node name as second argument."
      | [_; _] -> Error.type_error "Function `pipeline_node` expects a Pipeline as first argument."
      | _ -> Error.arity_error_named "pipeline_node" ~expected:2 ~received:(List.length args)
    ))
    env
