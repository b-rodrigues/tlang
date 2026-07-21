# diff_summary

Summarize Output Changes Across Builds

Compares the two most recent builds of a pipeline and returns a DataFrame summarizing which nodes changed, were added, or were removed.  Uses per-node Nix content hashes stored in build logs to detect changes without loading artifacts. Only loads artifacts for nodes that actually changed.

## Parameters

- **p** (`Pipeline`): The pipeline to compare builds for.


## Returns

A summary with columns: name, status, hash_a, hash_b.

