# tail

Get the last n rows/items

Returns the last n items from a List, Vector, or DataFrame. For DataFrames, it returns the bottom n rows.

## Parameters

- **data** (`DataFrame`): | List | Vector The collection to slice.
- **n** (`Int`): = 5 Number of items to return.

## Returns

| List | Vector A subset of the input containing the last n items.

## Examples

```t
tail([1, 2, 3, 4, 5, 6], n: 3)
-- Returns: [4, 5, 6]

df |> tail(n: 10)
```

