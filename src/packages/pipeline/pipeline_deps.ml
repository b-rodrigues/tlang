open Ast

let register env =
  Env.add "pipeline_deps"
    (make_builtin 1 (fun args _env ->
      match args with
      | [VPipeline { p_deps; _ }] ->
          VDict (List.map (fun (name, deps) ->
            (name, VList (List.map (fun d -> (None, VString d)) deps))
          ) p_deps)
      | [_] -> Error.type_error "Function `pipeline_deps` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_deps" ~expected:1 ~received:(List.length args)
    ))
    env
