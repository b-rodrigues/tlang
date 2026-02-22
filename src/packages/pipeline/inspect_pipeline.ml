open Ast

(*
--# Inspect Pipeline Logs
--#
--# Lists all available build logs in the `_pipeline/` directory.
--#
--# @name inspect_pipeline
--# @return :: List[String] A list of build log filenames, newest first.
--# @family pipeline
--# @export
*)
let register env =
  Env.add "inspect_pipeline"
    (make_builtin ~name:"inspect_pipeline" 0 (fun _args _env ->
      Builder.inspect_pipeline ()
    ))
    env
