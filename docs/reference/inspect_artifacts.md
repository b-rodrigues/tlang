# inspect_artifacts

Inspect Artifact Archive

Imports a pipeline archive into a temporary Nix store, extracts metadata (node name, store path, hash, size in bytes, and reference basenames) for each path, and returns a DataFrame of the results without modifying the local store.

## Parameters

- **archive_path** (`String`): The path to the artifact archive file.


## Returns

A DataFrame with columns `node` (String), `store_path` (String), `hash` (String), `size_bytes` (Int), and `references` (String).

