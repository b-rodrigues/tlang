# pipeline_copy

Copy Pipeline Node Artifacts to Local Directory

Copies built artifacts from the Nix store to a local directory for easier inspection. By default copies all nodes from the latest build to `pipeline-output/`.

## Parameters

- **node** (`String`): (Optional) The node name to copy. If NA, copies all nodes.

- **target_dir** (`String`): (Optional) The destination directory. Default is "pipeline-output".

- **dir_mode** (`String`): (Optional) POSIX mode for directories (e.g. "0755").

- **file_mode** (`String`): (Optional) POSIX mode for files (e.g. "0644").


## Returns

A success message or Error.

