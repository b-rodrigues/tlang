# write_registry

Registry Maintenance (Writer)

Writes a flat JSON object mapping node names to artifact paths.

## Parameters

- **path** (`String`): Destination file.
- **entries** (`List[(String, String)]`): Name-path pairs.

## Returns

`Result[Null, String]` Status.

