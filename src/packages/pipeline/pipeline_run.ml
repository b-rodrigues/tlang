open Ast

(*
--# Run Pipeline
--#
--# Re-executes a pipeline from start to finish.
--#
--# @name pipeline_run
--# @param p :: Pipeline The pipeline to run.
--# @return :: Pipeline The executed pipeline.
--# @family pipeline
--# @seealso pipeline_nodes
--# @export
*)
let register ~rerun_pipeline env =
  Env.add "pipeline_run"
    (make_builtin 1 (fun args env ->
      match args with
      | [VPipeline prev] -> rerun_pipeline env prev
      | [_] -> Error.type_error "Function `pipeline_run` expects a Pipeline."
      | _ -> Error.arity_error_named "pipeline_run" ~expected:1 ~received:(List.length args)
    ))
    env
