# ndarray

Create an N-dimensional array

Creates a new NDArray from a list or vector of data, optionally specifying the shape. If shape is not provided, it is inferred from the nested structure of the input list.

## Parameters

- **data** (`List`): | Vector The data to populate the array. Can be nested lists.
- **shape** (`List[Int]`): (Optional) The dimensions of the array.

## Returns

The created N-dimensional array.

## Examples

```t
ndarray([1, 2, 3, 4], shape: [2, 2])
ndarray([[1, 2], [3, 4]])
```

## See Also

[shape](shape.md), [reshape](reshape.md)

