open Ast

let register ~make_builtin ~make_error env =
  Env.add "pipeline_node"
    (make_builtin 2 (fun args _env ->
      match args with
      | [VPipeline { p_nodes; _ }; VString name] ->
          (match List.assoc_opt name p_nodes with
           | Some v -> v
           | None -> make_error KeyError (Printf.sprintf "node '%s' not found in Pipeline" name))
      | [VPipeline _; _] -> make_error TypeError "pipeline_node() expects a String node name as second argument"
      | [_; _] -> make_error TypeError "pipeline_node() expects a Pipeline as first argument"
      | _ -> make_error ArityError "pipeline_node() takes exactly 2 arguments"
    ))
    env
