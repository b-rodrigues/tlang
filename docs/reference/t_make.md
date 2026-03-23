# t_make

Build Pipeline Internally

Builds a pipeline, defaulting to `src/pipeline.t`. This command can also pass arguments to the underlying Nix build, such as `--max-jobs`.

## Parameters

- **filename** (`String`): The path to the pipeline file (defaults to "src/pipeline.t").

- **max_jobs** (`Int`): The maximum number of jobs for Nix to run in parallel.

- **max_cores** (`Int`): The maximum number of cores per job for Nix to use.


## Returns



## Examples

```t
t_make()
t_make(filename="src/pipeline2.t", max_jobs=2)
```

