open Ast

let register env =
  Env.add "pipeline_nodes"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VPipeline { p_nodes; _ }] ->
          VList (List.map (fun (name, _) -> (None, VString name)) p_nodes)
      | [_] -> Error.type_error "Function `pipeline_nodes` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_nodes" ~expected:1 ~received:(List.length args)
    ))
    env
