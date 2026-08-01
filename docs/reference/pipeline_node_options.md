# pipeline_node_options

Get Pipeline Node Options (read-back)

Returns a Dict describing the fully resolved configuration of a single pipeline node, after any `set_pipeline_global_options` merges have been applied.  This is the read-back companion to `set_pipeline_global_options`: what you merged in, you can read back out.  The returned Dict has the following keys: - `name` — the node name (String) - `runtime` — one of "T", "R", "Python", "Julia", "Quarto", "sh" (String) - `serializer` — e.g. "default", "pmml" (String) - `deserializer` — e.g. "default", "pmml" (String) - `noop` — whether the node is a no-op (Bool) - `deps` — names of nodes this node depends on (List of String) - `depth` — topological depth in the DAG (Int); roots are depth 0 - `command_type` — one of "command" or "script" (String) - `diagnostics` — node diagnostics (Dict) - `functions` — function files merged into the node (List of String) - `include` — included files (List of String) - `env_vars` — build environment variables (Dict) - `args` — runtime/tool arguments (Dict) - `shell` — shell interpreter, or NA when unset (String | NA) - `shell_args` — shell interpreter arguments (List of String) - `flake` — Nix flake path, or NA when unset (String | NA) - `provenance` — where each resolved option came from (Dict).  Combine options (`functions`, `include`, `shell_args`, `dependencies`) are grouped into `global`/`node` sub-lists; override options (`serializer`, `deserializer`, `shell`, `flake`, `noop`) map to a source String ("global" | "node") or NA when unset; `env_vars` and `args` map each key to its source String.  An unknown node name is a `TypeError` listing the valid node names.

## Parameters

- **pipeline** (`Pipeline`): The input pipeline.

- **node** (`String`): The node name to read back.


## Returns

The resolved node configuration.

## Examples

```t
pipeline_node_options(p, "n1")
```

## See Also

[pipeline_to_frame](pipeline_to_frame.html), [set_pipeline_global_options](set_pipeline_global_options.html)

