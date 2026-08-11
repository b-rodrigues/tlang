# pyn

Configure a Python Pipeline Node

A convenience wrapper around `node()` with `runtime = "Python"`. Used directly within a `pipeline { ... }` block to execute Python code.

## Parameters

- **command** (`Any`): (Optional) The expression to evaluate inside the Python node (must be enclosed in `<{ ... }>` blocks). Mutually exclusive with `script`.

- **script** (`String`): (Optional) Path to an external `.py` file to execute as the node body. Mutually exclusive with `command`. Sets the runtime to `Python` automatically.

- **serializer** (`String`): | Function (Optional) Custom serializer strategy. Built-in values include "default", "ipc", "parquet", and "pmml". Can be a string (e.g., "ipc") or an unquoted function name. Custom functions can also be used. Default = "default".

- **deserializer** (`String`): | Function (Optional) Custom deserializer strategy. Built-in values include "default", "ipc", "parquet", and "pmml". Can be a string (e.g., "ipc") or an unquoted function name. Custom functions can also be used. Default = "default".

- **functions** (`String`): | List[String] (Optional) Python files to source before execution.

- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.

- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.

- **flake** (`String`): (Optional) A Nix flake reference (e.g. "github:b-rodrigues/tlang") to use for this node's build environment. Default = NA (use project flake).


## Returns

A pipeline node configuration object. Must be used as a named binding inside a `pipeline { ... }` block; the Python code is executed by the pipeline builder, not immediately.

## See Also

[rn](rn.html), [node](node.html)

