# map_pattern

Map pattern stub

`map_pattern` can only be used as a `pattern=` argument inside `node()` to expand a node over the elements of a dependency (List, Vector, or DataFrame). Calling it directly returns a `TypeError`.

## Returns

A `TypeError` explaining that patterns are only valid inside `node()`.

## See Also

[expand_pipeline](expand_pipeline.html), [sample_pattern](sample_pattern.html), [tail_pattern](tail_pattern.html), [head_pattern](head_pattern.html), [slice_pattern](slice_pattern.html), [cross_pattern](cross_pattern.html)

