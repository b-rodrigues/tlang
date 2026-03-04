# list_files

List files in directory

Returns a list of files and directories in the specified path. Supports an optional regex pattern for filtering.

## Parameters

- **path** (`String`): [Optional] The directory to list. Defaults to ".".
- **pattern** (`String`): [Optional] Regex pattern to filter results.

## Returns:

Returns: List of filenames.

## Examples

```t
list_files(".", pattern = "\\.t$")
```

