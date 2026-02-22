open Ast

(*
--# Read Pipeline Node Artifact
--#
--# Reads a node artifact from `.t_pipeline_registry.json`.
--#
--# @name read_node
--# @param name :: String The node name.
--# @return :: Any The deserialized value.
--# @family pipeline
--# @seealso build_pipeline, load_node
--# @export
*)
let register env =
  Env.add "read_node"
    (make_builtin ~name:"read_node" 1 (fun args _env ->
      match args with
      | [VString name] -> Builder.read_node name
      | [_] -> Error.type_error "Function `read_node` expects a String node name."
      | _ -> Error.arity_error_named "read_node" ~expected:1 ~received:(List.length args)
    ))
    env
