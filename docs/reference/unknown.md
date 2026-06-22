# unknown

Expand pattern-based branching in a pipeline.

Patterned nodes using `map_pattern(dep)`, `cross_pattern(...)`, `slice_pattern(dep, [i1, i2, ...])`, `head_pattern(dep, n)`, `tail_pattern(dep, n)`, or `sample_pattern(dep, n)` are replaced with N branch copies, where N depends on the pattern type. Supports List, Vector, and DataFrame dependencies.  `populate_pipeline(p)`, `build_pipeline(p)`, and pipeline composition functions (`chain`, `parallel`, `union`, ...) now call this function automatically when they detect unexpanded patterns.

## Parameters

- **p** (`Pipeline`): The pipeline to expand.

- **to_script** (`String`): | NA = NA Optional file path to write the expanded pipeline script.


## Returns

The expanded pipeline with branches in place of patterned nodes.

## Examples

```t
p = pipeline { x = [1, 2, 3]; y = node(command = <{ x }>, pattern = map_pattern(x)) }
expanded = expand_pipeline(p)
pipeline_nodes(expanded)  -- ["x", "y_branch_1", "y_branch_2", "y_branch_3"]
```

