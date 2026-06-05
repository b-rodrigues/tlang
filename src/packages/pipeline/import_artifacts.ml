open Ast

(*
--# Import Pipeline Artifacts
--#
--# Imports a previously exported pipeline artifact archive into the local Nix
--# store and verifies that the pipeline nodes are now cached locally.
--# Supports two calling conventions: a 1-argument form for simple imports
--# (`import_artifacts(archive_path)`) and a 2-argument form for verification
--# (`import_artifacts(pipeline, archive_path)`) which verifies store path signatures.
--#
--# @name import_artifacts
--# @param target_or_archive :: Pipeline|String Either a Pipeline (2-arg form) or an archive path (1-arg form).
--# @param archive_path :: String (Optional) The source archive path. Required in the 2-arg form.
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
