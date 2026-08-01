# pipeline_validate

Validate a Pipeline

Checks a pipeline for structural errors without throwing. Returns a list of error messages. An empty list means the pipeline is valid.  Checks performed (shared with populate_pipeline and `t check` tier 1): - No dependency cycles - All referenced dependencies exist as nodes in the pipeline - Every node uses a known runtime - Cross-runtime dependencies declare an explicit deserializer - Multiple dependencies with a single non-dictionary deserializer strategy - Deserializer/format coherence across dependency edges (`text` is treated as format-agnostic raw bytes: shell/`capture = "stdout"` nodes may consume any format and typed nodes may read a shell node's raw output) - Referenced function/include/script files exist on the file system - The ^bin serializer is only used by fetchurl nodes

## Parameters

- **p** (`Pipeline`): The pipeline to validate.


## Returns

A list of validation error messages (empty = valid).

## Examples

```t
pipeline_validate(p)
```

## See Also

[pipeline_cycles](pipeline_cycles.html), [pipeline_assert](pipeline_assert.html)

