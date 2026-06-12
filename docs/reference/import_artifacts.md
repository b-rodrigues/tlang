# import_artifacts

Import Pipeline Artifacts

Imports a previously exported pipeline artifact archive into the local Nix store and verifies that the pipeline nodes are now cached locally. Supports two calling conventions: a 1-argument form for simple imports (`import_artifacts(archive_path)`) and a 2-argument form for verification (`import_artifacts(pipeline, archive_path)`) which verifies store path signatures.

## Parameters

- **target_or_archive** (`Pipeline|String`): Either a Pipeline (2-arg form) or an archive path (1-arg form).

- **archive_path** (`String`): (Optional) The source archive path. Required in the 2-arg form.


## Returns

A confirmation message describing the imported archive.

