# pipeline_config_to_frame

Convert Pipeline Config to DataFrame

Produces a DataFrame with one row per node, showing resolved configuration values and per-field provenance counts.  Extends [pipeline_to_frame] with provenance columns so queries like "which nodes got their serializer from global options?" can be answered directly in T.  Columns: - `name`, `runtime`, `depth`, `command_type` — identity (as in pipeline_to_frame) - `serializer`, `deserializer`, `noop`, `shell`, `flake` — resolved values - `prov_serializer`, ..., `prov_flake` — source ("node" / "global" / NA) - `n_deps`, `n_funcs`, `n_incs`, `n_env_vars`, `n_args`, `n_shell_args` — total counts (non-NA columns) - `n_*_global`, `n_*_node` — provenance counts for each list-type option  NOTE: `n_deps` is sourced from `p_deps` (which includes auto-inferred dependencies), while `n_deps_global` / `n_deps_node` are sourced from `prov_explicit_deps` (which only tracks explicitly-declared or globally-injected deps).  Consequently `n_deps` may exceed `n_deps_global + n_deps_node` when a node has auto-inferred edges. The other five list-count groups (`n_funcs`, `n_incs`, `n_env_vars`, `n_args`, `n_shell_args`) DO reconcile because they come from the same underlying lists as their provenance columns.

## Parameters

- **pipeline** (`Pipeline`): The pipeline to convert.


## Returns

A DataFrame with one row per node and config + provenance columns.

## Examples

```t
pipeline_config_to_frame(p)
```

## See Also

[pipeline_node_options](pipeline_node_options.html), [pipeline_to_frame](pipeline_to_frame.html)

