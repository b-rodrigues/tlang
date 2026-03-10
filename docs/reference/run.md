# run

Run a shell command

Executes a shell command and returns its stdout as a string. Raises a ShellError if the command fails (non-zero exit code).

## Parameters

- **cmd** (`String`): The shell command to execute.


## Returns

The stdout of the command.

## Examples

```t
branch = run("git rev-parse --abbrev-ref HEAD")
print(branch)
```

