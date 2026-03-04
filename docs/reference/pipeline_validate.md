# pipeline_validate

Validate a Pipeline

Checks a pipeline for structural errors without throwing. Returns a list of error messages. An empty list means the pipeline is valid.  Checks performed: - No dependency cycles - All referenced dependencies exist as nodes in the pipeline

## Parameters

- **p** (`Pipeline`): The pipeline to validate.

## Returns:

Returns: A list of validation error messages (empty = valid).

## Examples

```t
pipeline_validate(p)
```

## See Also

[pipeline_cycles](pipeline_cycles.html), [pipeline_assert](pipeline_assert.html)

