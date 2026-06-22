# expand_pipeline

Expand Pattern-Based Branching

Expands patterned nodes (using `map_pattern`, `cross_pattern`, `slice_pattern`, `head_pattern`, `tail_pattern`, or `sample_pattern`) into individual branch nodes. Each branch is named `<original>_branch_<N>`. Supports List, Vector, and DataFrame dependencies.

## Parameters

- **p** (`Pipeline`): The pipeline to expand.

- **to_script** (`String`): (Optional) File path to write the expanded pipeline script as a T source file.

## Returns

A Pipeline with branches in place of patterned nodes. `p_has_patterns` is set to `false`.

## See Also

[pipeline_nodes](pipeline_nodes.html), [populate_pipeline](populate_pipeline.html), [build_pipeline](build_pipeline.html)
