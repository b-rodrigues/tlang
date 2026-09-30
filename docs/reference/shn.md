# shn

Configure a Shell Pipeline Node

A convenience wrapper around `node()` with `runtime = "sh"`. Use `shn()` inside a `pipeline { ... }` block to run POSIX shell commands or `.sh` scripts, and optionally set `shell = "bash"` when Bash parsing is required.

## Parameters

- **command** (`Any`): (Optional) The shell command or raw shell script body to execute. Mutually exclusive with `script`.

- **script** (`String`): (Optional) Path to an external `.sh` file to execute as the node body. Mutually exclusive with `command`.

- **serializer** (`Symbol`): | Dict (Optional) Serializer strategy: a built-in (`default`, `^csv`, `^json`, `^ipc`, `^parquet`, `^pmml`, `^onnx`, `^bin`, `^text`, `^tlang`), an inline custom dict, or a quoted custom function `custom("name")` declared in `functions`. Bare function names are rejected. Default is `default`.

- **deserializer** (`Symbol`): | Dict (Optional) Deserializer strategy: same closed set as `serializer`. Default is `default`.

- **args** (`Dict`): | List (Optional) Runtime arguments. Lists become positional CLI arguments for exec-style nodes.

- **shell** (`String`): (Optional) Shell interpreter to invoke for shell-string mode or script-backed nodes. Default = "sh".

- **shell_args** (`List[String]`): (Optional) Additional arguments passed to the shell interpreter.

- **functions** (`String`): | List[String] (Optional) Additional files to include in the sandbox before execution.

- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.

- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.

- **flake** (`String`): (Optional) A Nix flake reference (e.g. "github:b-rodrigues/tlang") to use for this node's build environment. Default = NA (use project flake).


## Returns

A pipeline node configuration object. Must be used as a named binding inside a `pipeline { ... }` block; the shell command is executed by the pipeline builder, not immediately.

## See Also

[pyn](pyn.html), [rn](rn.html), [node](node.html)

