# node

Configure a Pipeline Node

Configure execution settings such as the runtime and custom serialized methods for a pipeline node. This function is typically used directly within a `pipeline { ... }` block to wrap expressions and enable cross-runtime evaluation. 

When a pipeline is built by Nix (`populate_pipeline(p, build = true)`), the arguments provided to `node()` are used to instantiate the Nix sandbox correctly.

## Parameters

- **command** (`Any`): The expression to evaluate inside the node (positional or named).
- **runtime** (`Symbol`, Optional): The runtime environment to execute the command. One of `T`, `R`, or `Python`. Default: `T`.
- **serializer** (`Symbol`, Optional): A function to overwrite the output artifact writing mechanism. Default: `default`.
- **deserializer** (`Symbol`, Optional): A function to override the artifact reading mechanism when depending on upstream nodes. Mandatory when depending on an upstream node with a different `runtime` value. Default: `default`.

## Returns

The evaluated return value of the `command` (during standard evaluation), or a runtime configured node artifact (during Nix sandbox builds).

## Examples

```t
p = pipeline {
  x = 10
  y = node(command = x + 5, runtime = T)
  z = node(
    command = build_model(y),
    runtime = R,
    deserializer = read_feather
  )
}
```

## See Also

[pipeline_run](pipeline_run.md)
