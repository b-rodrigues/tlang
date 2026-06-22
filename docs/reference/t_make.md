# t_make

Build and run a pipeline file

Reads, parses, evaluates and builds a T pipeline file. This is a high-level build orchestrator often used from the CLI (repl) to trigger a full project build. It supports a single dictionary argument for Nix specific build options. `src/pipeline.t` must call `populate_pipeline(...)` or `build_pipeline(...)`. If it only calls `populate_pipeline(...)` without `build=true`, `t_make()` emits a warning and continues after populating the pipeline.

## Parameters

- **filename** (`String`): The pipeline file path. Must be `src/pipeline.t`.

- **nix_options** (`Dict`): (Optional) A dictionary of Nix orchestration options:

- **verbose** (`Int`): The Nix build verbosity level. `0` is quiet; values > 0 enable internal node failure logs.

- **failfast** (`Bool`): Whether to stop immediately on evaluation errors (defaults to false).


## Returns



