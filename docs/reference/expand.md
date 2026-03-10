# expand

Create all combinations of values

Generates all unique combinations of the provided columns or expressions. Supports nesting() to only include combinations present in the data.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **...** (`Symbol`): | Vector | Call Specification of columns to expand.


## Returns

A DataFrame with all combinations.

## Examples

```t
expand(df, $type, $size)
expand(df, nesting($type, $size))
expand(df, $type, 2010:2012)
```

