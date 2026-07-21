# t_check

Check a T Script for Errors

Runs structural, wire-phase, schema, and environment checks on a T script. Returns the same diagnostics as the CLI `t check` command.

## Parameters

- **file** (`String`): The path to the .t file to check.

- **json** (`Bool`): = false Output diagnostics as JSON.

- **schema** (`Bool`): = false Enable column-level schema validation.

- **env** (`Bool`): = false Enable tproject.toml environment checks.

- **offline** (`Bool`): = false Prevent network access during env checks.


## Returns

The formatted diagnostics (text or JSON).

