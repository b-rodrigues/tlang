# filter

Filter rows

Retains rows that satisfy the predicate function.

## Parameters

- **df** (`DataFrame`): The input DataFrame.
- **predicate** (`Function`): A function returning Bool for each row.

## Returns:

Returns: The filtered DataFrame.

## Examples

```t
filter(mtcars, \(row) -> row.mpg > 20)
```

## See Also

[arrange](arrange.html), [select](select.html)

