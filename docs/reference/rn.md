# rn

Configure an R Pipeline Node

A convenience wrapper around `node()` with `runtime = "R"`. Used directly within a `pipeline { ... }` block to execute R code.

## Parameters

- **command** (`Any`): The expression to evaluate inside the R node (must be enclosed in `<{ ... }>` blocks).
- **serializer** (`Symbol`): (Optional) Custom serializer function. Default: default.
- **deserializer** (`Symbol`): (Optional) Custom deserializer function. Default: default.
- **functions** (`String`): | List[String] (Optional) R scripts to source before execution.
- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.
- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default: false.

## Returns

The evaluated return value of the command.

## See Also

[pyn](pyn.md), [node](node.md)

