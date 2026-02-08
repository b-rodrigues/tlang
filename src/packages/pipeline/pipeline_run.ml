open Ast

let register ~rerun_pipeline env =
  Env.add "pipeline_run"
    (make_builtin 1 (fun args env ->
      match args with
      | [VPipeline prev] -> rerun_pipeline env prev
      | [_] -> make_error TypeError "pipeline_run() expects a Pipeline"
      | _ -> make_error ArityError "pipeline_run() takes exactly 1 argument"
    ))
    env
