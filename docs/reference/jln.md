# jln

Configure a Julia Pipeline Node

A convenience wrapper around `node()` with `runtime = "Julia"`. Used directly within a `pipeline { ... }` block to execute Julia code.

## Parameters

- **command** (`Any`): (Optional) The expression to evaluate inside the Julia node (must be enclosed in `<{ ... }>` blocks). Mutually exclusive with `script`.

- **script** (`String`): (Optional) Path to an external `.jl` file to execute as the node body. Mutually exclusive with `command`. Sets the runtime to `Julia` automatically.

- **serializer** (`Symbol`): (Optional) Custom serializer strategy. Use `^`-prefixed symbols (e.g., `^csv`, `^json`, `^arrow`, `^onnx`). Default = runtime-native binary serialization (`jl_serialize`).

- **deserializer** (`Symbol`): (Optional) Custom deserializer strategy. Use `^`-prefixed symbols (e.g., `^csv`, `^json`, `^arrow`, `^onnx`). Default = runtime-native binary deserialization.

- **functions** (`String`): | List[String] (Optional) Julia files to source before execution.

- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.

- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.


## Returns

A pipeline node configuration object. Must be used as a named binding inside a `pipeline { ... }` block; the Julia code is executed by the pipeline builder, not immediately.

## See Also

[pyn](pyn.html), [rn](rn.html), [node](node.html)

