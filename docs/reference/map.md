# map

Map a function over a list

Applies a function to each element of a list and returns a new list of results.

## Parameters

- **list** (`List`): The input list.
- **fn** (`Function`): The function to apply to each element.

## Returns

The list of results.

## Examples

```t
map([1, 2, 3], fn(x) -> x * 2)
-- Returns: [2, 4, 6]
```

