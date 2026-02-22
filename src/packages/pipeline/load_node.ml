open Ast

(*
--# Load Pipeline Node Artifact
--#
--# Loads a node artifact by name. Currently this is an alias of `read_node`.
--#
--# @name load_node
--# @param name :: String The node name.
--# @return :: Any The deserialized value.
--# @family pipeline
--# @seealso build_pipeline, read_node
--# @export
*)
let register env =
  Env.add "load_node"
    (make_builtin ~name:"load_node" 1 (fun args _env ->
      match args with
      | [VString name] -> Builder.read_node name
      | [_] -> Error.type_error "Function `load_node` expects a String node name."
      | _ -> Error.arity_error_named "load_node" ~expected:1 ~received:(List.length args)
    ))
    env
