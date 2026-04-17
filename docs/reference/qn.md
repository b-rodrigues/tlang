# qn

Configure a Quarto Pipeline Node

A convenience wrapper around `node()` with `runtime = "Quarto"`. Used directly within a `pipeline { ... }` block to render Quarto documents.

## Parameters

- **script** (`String`): (Optional) Path to an external `.qmd` file to render. Mutually exclusive with `command`.

- **serializer** (`String`): | Function (Optional) Custom serializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **deserializer** (`String`): | Function (Optional) Custom deserializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **env_vars** (`Dict`): (Optional) Environment variables to pass into the sandbox.

- **args** (`Dict`): (Optional) Runtime/tool arguments. Use this to pass Quarto CLI arguments such as `subcommand`, `path`, `to`, and additional options. `output_dir` is reserved and managed automatically so the rendered result is stored as the node artifact.

- **functions** (`String`): | List[String] (Optional) Files to source before execution.

- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.

- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.


## Returns

The evaluated return value of the command.

## See Also

[node](node.html), [rn](rn.html), [pyn](pyn.html), [shn](shn.html)
