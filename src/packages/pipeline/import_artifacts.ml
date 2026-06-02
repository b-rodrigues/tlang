open Ast

(*
--# Import Pipeline Artifacts
--#
--# Imports a previously exported pipeline artifact archive into the local Nix
--# store and verifies that the pipeline nodes are now cached locally.
--#
--# @name import_artifacts
--# @param p :: Pipeline The pipeline whose artifacts should be restored.
--# @param archive_path :: String The source archive path.
--# @return :: String A confirmation message describing the imported archive.
--# @family pipeline
--# @export
*)
let register env =
  Env.add "import_artifacts"
    (make_builtin ~name:"import_artifacts" 2 (fun args _env ->
      match args with
      | [VPipeline p; VString archive_path] ->
          (match Builder_artifacts.import_artifacts p archive_path with
           | Ok message -> VString message
           | Error err -> Error.make_error err.code err.message)
      | [VPipeline _; _] ->
          Error.type_error "Function `import_artifacts` expects `archive_path` to be a String."
      | [_; _] ->
          Error.type_error "Function `import_artifacts` expects a Pipeline as first argument."
      | _ ->
          Error.arity_error_named "import_artifacts" 2 (List.length args)
    ))
    env
