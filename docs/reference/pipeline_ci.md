# pipeline_ci

Generates CI-ready Nix files for a T pipeline.

```t
pipeline_ci(p, output_dir = "_pipeline/ci", workflow = false, cache = na())
```

`pipeline_ci()` reuses an existing `_pipeline/pipeline.nix` when `build_pipeline()` or `populate_pipeline()` has already created one. If it is missing, `pipeline_ci()` populates it once, then writes a standalone flake at `output_dir/flake.nix`. The generated flake exposes `packages.pipeline` and `checks.pipeline`, so any Nix-enabled CI runner can build the pipeline without invoking T:

```bash
nix build ./_pipeline/ci#pipeline --accept-flake-config --print-build-logs
```

Set `workflow = true` to also write `.github/workflows/t-pipeline.yml`. Set `cache = "my-cache"` to include Cachix configuration in that workflow.

The repository also includes `.github/actions/run-t-pipeline/action.yml`, a composite GitHub Action that installs Nix, optionally configures Cachix, and builds the generated pipeline flake.


The returned dictionary includes `generated_pipeline_nix`, which is `true` only when `pipeline_ci()` had to create `_pipeline/pipeline.nix`; it is `false` when an existing pipeline Nix file was reused.
