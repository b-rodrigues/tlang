# export_artifacts

Export Pipeline Artifacts

Exports the cached Nix artifacts of a pipeline to a portable archive file. All pipeline nodes must already exist in the local store.

## Parameters

- **p** (`Pipeline`): The pipeline whose cached artifacts should be exported.

- **archive_path** (`String`): The destination archive path.


## Returns

A confirmation message describing the exported archive.

