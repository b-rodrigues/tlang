# pipeline_to_ga

Export Pipeline as GitHub Actions Workflow

Generates a GitHub Actions CI workflow YAML that runs the pipeline on push/PR. The workflow restores cached Nix artifacts from the `t-runs` branch, executes the pipeline, and re-exports updated artifacts back to `t-runs`. Use the `file` parameter to write the YAML directly to `.github/workflows/<name>.yml`.

## Parameters

- **pipeline_script** (`String`): (Optional) Path to the pipeline T script. Default "src/pipeline.t".

- **name** (`String`): (Optional) Project name. Auto-detected from tproject.toml when omitted.

- **file** (`String`): (Optional) Output file path. Defaults to ".github/workflows/<name>.yml". Pass an empty string ("") to get the YAML back as a string.


## Returns

The YAML workflow content or a confirmation string.

## Examples

```t
pipeline_to_ga()
pipeline_to_ga("src/run.t")
pipeline_to_ga(name = "my-project")
pipeline_to_ga(file = ".github/workflows/ci.yml")
```

