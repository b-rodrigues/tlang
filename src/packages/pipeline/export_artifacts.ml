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
      | [VPipeline p; VString archive_path] ->
          (match Builder_artifacts.export_artifacts p archive_path with
           | Ok message -> VString message
           | Error err -> Error.make_error err.code err.message)
      | [VPipeline _; _] ->
          Error.type_error "Function `export_artifacts` expects `archive_path` to be a String."
      | [_; _] ->
          Error.type_error "Function `export_artifacts` expects a Pipeline as first argument."
      | _ ->
          Error.arity_error_named "export_artifacts" 2 (List.length args)
    ))
    env
