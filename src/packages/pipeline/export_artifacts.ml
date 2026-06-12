open Ast

(*
--# Export Pipeline Artifacts
--#
--# Exports the cached Nix artifacts of a pipeline to a portable archive file.
--# All pipeline nodes must already exist in the local store.
--#
--# @name export_artifacts
--# @param p :: Pipeline The pipeline whose cached artifacts should be exported.
--# @param archive_path :: String The destination archive path.
--# @return :: String A confirmation message describing the exported archive.
--# @family pipeline
--# @export
*)
let register env =
  Env.add "export_artifacts"
    (make_builtin ~name:"export_artifacts" 2 (fun args _env ->
      match args with
      | [target_val; VString archive_path] ->
          (match Builder_artifacts.export_artifacts target_val archive_path with
           | Ok message -> VString message
           | Error err -> Error.make_error err.code err.message)
      | [first; second] ->
          Error.type_error
            (Printf.sprintf "Function `export_artifacts` expects a Pipeline and a String, but got %s and %s."
               (Utils.type_name first) (Utils.type_name second))
      | _ ->
          Error.arity_error_named "export_artifacts" 2 (List.length args)
    ))
    env
