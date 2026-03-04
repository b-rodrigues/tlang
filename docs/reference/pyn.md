# pyn

Configure a Python Pipeline Node

A convenience wrapper around `node()` with `runtime = "Python"`. Used directly within a `pipeline { ... }` block to execute Python code.

## Parameters

- **command** (`Any`): (Optional) The expression to evaluate inside the Python node (must be enclosed in `<{ ... }>` blocks). Mutually exclusive with `script`.
- **script** (`String`): (Optional) Path to an external `.py` file to execute as the node body. Mutually exclusive with `command`. Sets the runtime to `Python` automatically.
- **serializer** (`Symbol`): (Optional) Custom serializer function. Default = default.
- **deserializer** (`Symbol`): (Optional) Custom deserializer function. Default = default.
- **functions** (`String`): | List[String] (Optional) Python files to source before execution.
- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.
- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.

## Returns:

Returns: The evaluated return value of the command.

## See Also

[rn](rn.html), [node](node.html)

