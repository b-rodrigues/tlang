# t_make

Build Pipeline Internally

Builds the `src/pipeline.t` pipeline entrypoint.

`src/pipeline.t` must call `populate_pipeline(...)` or `build_pipeline(...)`.
If it only calls `populate_pipeline(...)` without `build = true`, `t_make()`
emits a warning and continues after populating the pipeline.

## Parameters

- **filename** (`String`): (Optional) The pipeline build script path. Must be `src/pipeline.t`.
