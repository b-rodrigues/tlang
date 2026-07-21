# t_diff

Compare Two Builds of a Pipeline

Compares two builds of a pipeline and returns a summary of which nodes changed, were added, or were removed. Uses per-node Nix content hashes.

## Parameters

- **file** (`String`): The path to the .t file to diff.

- **json** (`Bool`): = false Output diff as JSON.

- **log_a** (`Int`): = 2 Rank of the first (older) build log.

- **log_b** (`Int`): = 1 Rank of the second (newer) build log.


## Returns

The formatted diff (text or JSON).

