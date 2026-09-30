# rn

Configure an R Pipeline Node

A convenience wrapper around `node()` with `runtime = "R"`. Used directly within a `pipeline { ... }` block to execute R code.

## Parameters

- **command** (`Any`): (Optional) The expression to evaluate inside the R node (must be enclosed in `<{ ... }>` blocks). Mutually exclusive with `script`.

- **script** (`String`): (Optional) Path to an external `.R` file to execute as the node body. Mutually exclusive with `command`. Sets the runtime to `R` automatically.

- **serializer** (`Symbol`): | Dict (Optional) Serializer strategy: a built-in (`default`, `^csv`, `^json`, `^ipc`, `^parquet`, `^pmml`, `^onnx`, `^bin`, `^text`, `^tlang`), an inline custom dict, or a quoted custom function `custom("name")` declared in `functions`. Bare function names are rejected. Default is `default`.

- **deserializer** (`Symbol`): | Dict (Optional) Deserializer strategy: same closed set as `serializer`. Default is `default`.

- **functions** (`String`): | List[String] (Optional) R scripts to source before execution.

- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.

- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.

- **flake** (`String`): (Optional) A Nix flake reference (e.g. "github:b-rodrigues/tlang") to use for this node's build environment. Default = NA (use project flake).


## Returns

A pipeline node configuration object. Must be used as a named binding inside a `pipeline { ... }` block; the R code is executed by the pipeline builder, not immediately.

## See Also

[pyn](pyn.html), [node](node.html)

