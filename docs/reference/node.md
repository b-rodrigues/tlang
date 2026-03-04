# node

Configure a Pipeline Node

Configure execution settings such as the runtime and custom serialized methods for a pipeline node. This function is typically used directly within a `pipeline { ... }` block to wrap expressions and enable cross-runtime evaluation.

## Parameters

- **command** (`Any`): (Optional) The expression to evaluate inside the node. Mutually exclusive with `script`.
- **script** (`String`): (Optional) Path to an external `.R` or `.py` file to execute as the node body. Mutually exclusive with `command`. The runtime is auto-detected from the file extension when not explicitly provided.
- **runtime** (`Symbol`): (Optional) The runtime environment (T, R, Python). Default = T.
- **serializer** (`Symbol`): (Optional) Custom serializer function. Default = default.
- **deserializer** (`Symbol`): (Optional) Custom deserializer function. Default = default.
- **functions** (`String`): | List[String] (Optional) Files to source before execution.
- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.
- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.

## Returns:

Returns: The evaluated return value of the command.

