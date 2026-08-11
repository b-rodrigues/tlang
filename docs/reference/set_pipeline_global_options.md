# set_pipeline_global_options

Set Pipeline Global Options (pure)

Pure function that returns a new pipeline with the given defaults merged into nodes.  The original pipeline is not modified.  By default the settings are merged into every node; pass `runtimes` and/or `nodes` to restrict the merge to a subset (union semantics when both are given).  Omitting both scoping arguments (or passing `na()`) targets every node; an explicitly empty list (`nodes = []`) targets no nodes.  Merge semantics vary per option: * Combine (prepend): `functions`, `include`, `env_vars`, `args`, `shell_args`, `dependencies`.  Global values come first; per-node values follow (for same-key dict entries, the later per-node value wins). * Override: `serializer`, `deserializer`, `shell`, `flake`.  A provided global value replaces the node's per-node value entirely. * Force-only: `noop`.  `noop = true` forces nodes to no-op; `noop = false` has no effect and cannot un-set a per-node `noop = true`.

## Parameters

- **pipeline** (`Pipeline`): The input pipeline.

- **functions** (`Dict`): (Optional) Combine (prepend). Runtime-shorthand to

- **include** (`String`): | List[String] (Optional) Combine (prepend). File

- **env_vars** (`Dict`): (Optional) Combine (prepend). Environment variables.

- **serializer** (`String`): | Symbol (Optional) Override. Default serializer;

- **deserializer** (`String`): | Symbol (Optional) Override. Default deserializer;

- **noop** (`Bool`): (Optional) Force-only. If true, nodes become no-ops.

- **args** (`Dict`): (Optional) Combine (prepend). Runtime arguments. Per-node

- **shell** (`String`): (Optional) Override. Shell interpreter.

- **shell_args** (`String`): | List[String] (Optional) Combine (prepend). Shell

- **flake** (`String`): (Optional) Override. Nix flake path.

- **dependencies** (`String`): | List[String] (Optional) Combine (prepend).

- **runtimes** (`String`): | List[String] (Optional) Scope the merge to nodes

- **nodes** (`String`): | List[String] (Optional) Scope the merge to exactly


## Returns

A new pipeline with the settings merged into the target nodes.

## Examples

```t
set_pipeline_global_options(p, runtimes = ["R"], serializer = ^ipc)
set_pipeline_global_options(p, nodes = ["n1", "n3"], noop = true)
```

