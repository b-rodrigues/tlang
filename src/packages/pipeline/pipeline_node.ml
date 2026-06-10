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
    (make_builtin ~name:"pipeline_node" 2 (fun args _env ->
      match args with
      | [VPipeline p; VString name] ->
          let v = Eval.pipeline_get_node_value (ref _env) p name in
          (match v with
           | VNA _ -> Error.make_error KeyError (Printf.sprintf "Node `%s` not found in Pipeline." name)
           | _ -> v)
      | [VPipeline _; other] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_node` expects a String node name as second argument, but got %s."
               (Utils.type_name other))
      | [first; _] ->
          Error.type_error
            (Printf.sprintf "Function `pipeline_node` expects a Pipeline as first argument, but got %s."
               (Utils.type_name first))
      | _ -> Error.arity_error_named "pipeline_node" 2 (List.length args)
    ))
    env
