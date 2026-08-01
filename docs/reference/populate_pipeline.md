# populate_pipeline

Prepare Pipeline Infrastructure

Writes the pipeline's Nix expression into `_pipeline/` and, when `build = true`, materializes all nodes. Returns a BuildLog on success or a DataFrame of planned build actions when a `dry_run` option is set.

## Parameters

- **p** (`Pipeline`): The pipeline to populate.

- **build** (`Bool`): = false If `true`, triggers a Nix build of all nodes.

- **verbose** (`Int`): = 0 Nix build verbosity level (`0` = quiet, higher values print node stdout/stderr).

- **nix_options** (`Dict`): (Optional) Nix build options. Supported keys: `targets`, `force`, `dry_run`, `max_jobs`, `cache`, `builders`, `keep_env`, `sandbox`.

- **dry_run** (`Bool`): (Optional) If `true`, returns a planned build actions DataFrame instead of building.

- **pipeline_name** (`String`): (Optional) Explicit name for the pipeline.


## Returns

| BuildLog | DataFrame Success message, BuildLog, or planned-actions DataFrame.

## Examples

```t
populate_pipeline(p)
populate_pipeline(p, build = true)
```

## See Also

[pipeline_run](pipeline_run.html), [build_pipeline](build_pipeline.html)

