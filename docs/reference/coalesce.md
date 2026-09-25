# coalesce

Coalesce missing values

Returns the first non-NA value at each position across inputs. All inputs must be Vectors or Lists of equal length.

## Parameters

- **...** (`Vector`): | List Vectors to coalesce in priority order.


## Returns

The first non-NA value per position.

## Examples

```t
coalesce([1, NA, 3], [10, 20, 30])
```

