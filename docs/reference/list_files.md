# list_files

List files in directory

Returns a list of files and directories in the specified path. Supports an optional regex pattern for filtering. Returns a FileError value when the directory cannot be read.

## Parameters

- **path** (`String`): [Optional] The directory to list. Defaults to ".".

- **pattern** (`String`): [Optional] Regex pattern to filter results.


## Returns

List of filenames.

## Examples

```t
list_files(".", pattern = "\\.t$")
```

