# node

Configure a Pipeline Node

Configure execution settings such as the runtime and custom serialized methods for a pipeline node. This function is typically used directly within a `pipeline { ... }` block to wrap expressions, enable cross-runtime evaluation, run shell/CLI steps, and optionally render a `.qmd` document via `runtime = Quarto`.

## Parameters

- **command** (`Any`): (Optional) The expression to evaluate inside the node. Mutually exclusive with `script`.

- **script** (`String`): (Optional) Path to an external `.R`, `.py`, `.sh`, or `.qmd` file to execute as the node body. Mutually exclusive with `command`. The runtime is auto-detected from the file extension when not explicitly provided.

- **runtime** (`Symbol`): (Optional) The runtime environment (`T`, `R`, `Python`, `sh`, or `Quarto`). Default = `T`.

- **serializer** (`Symbol`): (Optional) Custom serializer function. Default = default.

- **deserializer** (`Symbol`): (Optional) Custom deserializer function. Default = default.

- **args** (`Dict | List`): (Optional) Runtime/tool arguments. For `runtime = sh`, a list becomes positional CLI arguments and a dict becomes named runtime metadata. For Quarto, use this to pass CLI arguments such as `subcommand`, `path`, and additional options. `output_dir` is reserved and managed automatically so the rendered result is stored as the node artifact.

- **shell** (`String`): (Optional) Shell interpreter for `runtime = sh`. Defaults to `sh`, but you can set `shell = "bash"` when you need Bash parsing.

- **shell_args** (`List[String]`): (Optional) Extra arguments passed to the shell interpreter, such as `["-lc"]`.

- **functions** (`String`): | List[String] (Optional) Files to source before execution.

- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.

- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.


## Returns

The evaluated return value of the command.

## Notes

- `shn(...)` is a convenience wrapper for `node(runtime = sh, ...)`.
- Shell nodes default to `serializer = text`, making them a good fit for reports and CLI output.
