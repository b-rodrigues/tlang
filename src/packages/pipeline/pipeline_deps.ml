open Ast

let register env =
  Env.add "pipeline_deps"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VPipeline { p_deps; _ }] ->
          VDict (List.map (fun (name, deps) ->
            (name, VList (List.map (fun d -> (None, VString d)) deps))
          ) p_deps)
      | [_] -> make_error TypeError "pipeline_deps() expects a Pipeline"
      | _ -> make_error ArityError "pipeline_deps() takes exactly 1 argument"
    ))
    env
