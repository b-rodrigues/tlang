# head

Get the first n rows/items

Returns the first n items from a List, Vector, or DataFrame. For DataFrames, it returns the top n rows.

## Parameters

- **data** (`DataFrame`): | List | Vector The collection to slice.
- **n** (`Int`): = 5 Number of items to return.

## Returns

| List | Vector A subset of the input containing the first n items.

## Examples

```t
head([1, 2, 3, 4, 5, 6], n: 3)
-- Returns: [1, 2, 3]

df |> head(n: 10)
```

