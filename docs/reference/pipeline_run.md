# pipeline_run

Run Pipeline

Re-executes a pipeline from start to finish. When any Nix orchestration argument is supplied, delegates to a Nix build instead of in-memory re-eval.

## Parameters

- **p** (`Pipeline`): The pipeline to run.

- **nix_options** (`Dict`): (Optional) A dictionary of Nix orchestration options:


## Returns

The executed pipeline, or a dry-run plan DataFrame.

## See Also

[pipeline_nodes](pipeline_nodes.html)

