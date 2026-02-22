# build_pipeline_internal

Internal Build Logic

Executes `nix-build` to materialize the pipeline. Records build logs and store paths for traceability.

## Parameters

- **p** (`Pipeline`): The pipeline result from evaluation.

## Returns

String] The store path on success, or an error message.

