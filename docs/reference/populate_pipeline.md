# populate_pipeline

Populate Pipeline

Generates the `_pipeline/` directory with `pipeline.nix` and `dag.json`. Optionally builds the pipeline.

## Parameters

- **p** (`Pipeline`): The pipeline to populate.
- **build** (`Bool`): (Optional) Whether to trigger the Nix build immediately. Defaults to false.

## Returns

A status message or the output path if build=true.

## Notes

`populate_pipeline` performs several validation checks before generating the Nix files:
- **File Existence**: Verifies that all files specified in `functions` or `include` arguments of any node actually exist on the file system.
- **Custom Function Warning**: Issues a warning to `stderr` if a node uses a custom `serializer` or `deserializer` but does not provide any companion `functions` files.

