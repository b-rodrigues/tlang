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
    (make_builtin ~name:"import_artifacts" ~variadic:true 2 (fun args _env ->
      match args with
      | [VString archive_path] ->
          (match Builder_artifacts.import_artifacts_no_verify archive_path with
           | Ok message -> VString message
           | Error err -> Error.make_error err.code err.message)
      | [target_val; VString archive_path] ->
          (match Builder_artifacts.import_artifacts target_val archive_path with
           | Ok message -> VString message
           | Error err -> Error.make_error err.code err.message)
      | [_; _] ->
          Error.type_error "Function `import_artifacts` expects the second argument to be a String."
      | [_] ->
          Error.type_error "Function `import_artifacts` expects a String argument."
      | _ ->
          Error.arity_error_named "import_artifacts" 2 (List.length args)
    ))
    env
