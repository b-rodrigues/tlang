open Ast

let register ~make_builtin ~make_error env =
  Env.add "pipeline_nodes"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VPipeline { p_nodes; _ }] ->
          VList (List.map (fun (name, _) -> (None, VString name)) p_nodes)
      | [_] -> make_error TypeError "pipeline_nodes() expects a Pipeline"
      | _ -> make_error ArityError "pipeline_nodes() takes exactly 1 argument"
    ))
    env
