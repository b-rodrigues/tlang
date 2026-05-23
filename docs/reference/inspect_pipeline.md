# inspect_pipeline

Inspect Pipeline Schema (Static)

Returns a DataFrame outlining the static compile-time configuration of the pipeline.

## Parameters

- **p** (`Pipeline`): The pipeline to inspect statically.


## Returns

A DataFrame with columns = node, runtime, serializer, dependencies, has_script.

