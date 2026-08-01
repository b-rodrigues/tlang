# build_pipeline

Build Pipeline

Shorthand for `populate_pipeline(p, build = true)`. Materializes all nodes of the pipeline via Nix and returns a `BuildLog` (or a DataFrame of build stats). Recommended for scripts run with `t run`.

## Parameters

- **p** (`Pipeline`): The pipeline to build.

- **verbose** (`Int`): = 0 Nix build verbosity level (`0` = quiet, higher values print node stdout/stderr).

- **nix_options** (`Dict`): (Optional) Nix build options. Supported keys: `targets`, `force`, `dry_run`, `max_jobs`, `cache`, `builders`, `keep_env`, `sandbox`.

- **dry_run** (`Bool`): (Optional) If `true`, returns a planned build actions DataFrame instead of building.

- **pipeline_name** (`String`): (Optional) Explicit name for the pipeline.


## Returns

| DataFrame A BuildLog of the build, or a planned-actions DataFrame when `dry_run` is set.

## Examples

```t
build_pipeline(p)
```

## See Also

[pipeline_run](pipeline_run.html), [populate_pipeline](populate_pipeline.html)

