# reshape

Reshape an NDArray

Returns a new NDArray with the same data but different dimensions. The total number of elements must remain the same.

## Parameters

- **array** (`NDArray`): The array to reshape.
- **shape** (`List[Int]`): The new dimensions.

## Returns

A new array with the specified shape.

## Examples

```t
reshape(arr, [4, 1])
```

## See Also

[shape](shape.md), [ndarray](ndarray.md)

