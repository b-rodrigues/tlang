# pipeline_assert

Assert Pipeline Validity

Validates the pipeline and returns it unchanged if valid. Throws the first validation error found if the pipeline is invalid.

## Parameters

- **p** (`Pipeline`): The pipeline to validate.


## Returns

The same pipeline if valid.

## Examples

```t
p |> pipeline_assert
```

## See Also

[pipeline_cycles](pipeline_cycles.html), [pipeline_validate](pipeline_validate.html)

