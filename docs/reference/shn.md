# shn

Configure a Shell Pipeline Node

A convenience wrapper around `node()` with `runtime = "sh"`. Use `shn()` inside a `pipeline { ... }` block to run POSIX shell commands, inline shell scripts, or external `.sh` files.

## Parameters

- **command** (`Any`): (Optional) The shell command or raw shell script body to execute. Mutually exclusive with `script`.

- **script** (`String`): (Optional) Path to an external `.sh` file to execute as the node body. Mutually exclusive with `command`.

- **serializer** (`Symbol`): (Optional) Custom serializer function. Default = `text`.

- **deserializer** (`Symbol`): (Optional) Custom deserializer function. Default = `default`.

- **args** (`Dict | List`): (Optional) Runtime arguments. Lists become positional CLI arguments for exec-style shell nodes.

- **shell** (`String`): (Optional) Shell interpreter to invoke. Default = `sh`. Set `shell = "bash"` when you need Bash-specific parsing.

- **shell_args** (`List[String]`): (Optional) Extra arguments for the shell interpreter, such as `["-lc"]`.

- **functions** (`String | List[String]`): (Optional) Additional files to include in the sandbox before execution.

- **include** (`String | List[String]`): (Optional) Additional files for the sandbox.

- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = `false`.

## Returns

The evaluated return value of the command.

## See Also

[node](node.html), [rn](rn.html), [pyn](pyn.html)
