# node

Configure a Pipeline Node

Configure execution settings such as the runtime and custom serialized methods for a pipeline node. This function is typically used directly within a `pipeline { ... }` block to wrap expressions and enable cross-runtime evaluation. 

When a pipeline is built by Nix (`populate_pipeline(p, build = true)`), the arguments provided to `node()` are used to instantiate the Nix sandbox correctly.

## Parameters

- **command** (`Any`): The expression to evaluate inside the node (positional or named).
- **runtime** (`Symbol`, Optional): The runtime environment to execute the command. One of `T`, `R`, or `Python`. Default: `T`.
- **serializer** (`Symbol`, Optional): A function to overwrite the output artifact writing mechanism. Default: `default`.
- **deserializer** (`Symbol`, Optional): A function to override the artifact reading mechanism when depending on upstream nodes. Mandatory when depending on an upstream node with a different `runtime` value. Default: `default`.
- **functions** (`String` or `List[String]`, Optional): File paths containing custom code / functions to execute and inject before running the `command`. Used usually when `serializer` and `deserializer` are custom functions defined outside the standard environment.
- **include** (`String` or `List[String]`, Optional): Additional file paths to copy into the sandbox alongside the source code. Does not execute these natively.
- **noop** (`Boolean`, Optional): Mark this node (and by extension all of its dependencies) to skip Nix execution entirely, generating only a lightweight stub instead of triggering actual evaluation workflows. Default: `false`.

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
    deserializer = read_feather,
    functions = ["my_utils.R"],
    include = "config.yml"
  )
}
```

## See Also

[pipeline_run](pipeline_run.md)
