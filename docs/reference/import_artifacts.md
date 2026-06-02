# import_artifacts

Import Pipeline Artifacts

Imports a previously exported pipeline artifact archive into the local Nix store
and verifies that the pipeline nodes are now cached locally.

## Parameters

- **p** (`Pipeline`): The pipeline whose artifacts should be restored.

- **archive_path** (`String`): The source archive path.

## Returns

A confirmation message describing the imported archive.

