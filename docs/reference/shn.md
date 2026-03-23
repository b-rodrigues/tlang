# shn

Configure a Shell Pipeline Node

A convenience wrapper around `node()` with `runtime = "sh"`. Use `shn()` inside a `pipeline { ... }` block to run POSIX shell commands or `.sh` scripts, and optionally set `shell = "bash"` when Bash parsing is required.

## Parameters

- **command** (`Any`): (Optional) The shell command or raw shell script body to execute. Mutually exclusive with `script`.

- **script** (`String`): (Optional) Path to an external `.sh` file to execute as the node body. Mutually exclusive with `command`.

- **serializer** (`String`): | Function (Optional) Custom serializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **deserializer** (`String`): | Function (Optional) Custom deserializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **args** (`Dict`): | List (Optional) Runtime arguments. Lists become positional CLI arguments for exec-style nodes.

- **shell** (`String`): (Optional) Shell interpreter to invoke for shell-string mode or script-backed nodes. Default = "sh".

- **shell_args** (`List[String]`): (Optional) Additional arguments passed to the shell interpreter.

- **functions** (`String`): | List[String] (Optional) Additional files to include in the sandbox before execution.

- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.

- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.


## Returns

The evaluated return value of the command.

## See Also

[pyn](pyn.html), [rn](rn.html), [node](node.html)

