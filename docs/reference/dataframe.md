# dataframe

Create a DataFrame

Constructs a DataFrame from either a list of rows (Dicts) or a Dictionary of columns (Vectors/Lists).

## Parameters

- **data** (`List[Dict]|Dict`): The data rows or columns.


## Returns

The created DataFrame.

## Examples

```t
# Row-wise construction:
df = dataframe([
{"a": 1, "b": 2},
{"a": 3, "b": 4}
])

# Column-wise construction (supported for VDict):
df2 = dataframe([a: [1, 3], b = [2, 4]])

# Scalar values are recycled to match other column lengths:
df3 = dataframe([x: [1, 2, 3], constant = 0])
```

## See Also

[read_csv](read_csv.html)

