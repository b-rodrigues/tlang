# path_abs

## Parameters

- **path** (`String`): A relative or absolute path.

## Returns:

Returns: The absolute path resolved against the current working directory.

## Examples

```t
path_abs("data.csv")          # => "/cwd/data.csv"
path_abs("/already/absolute") # => "/already/absolute"
```

