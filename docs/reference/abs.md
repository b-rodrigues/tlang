# abs

Absolute value

Returns the absolute value of a number or vector/ndarray elements. Raises a TypeError if an NA value is encountered. Use `filter` or explicit missingness handling before calling `abs` on data that may contain NAs.

## Parameters

- **x** (`Number`): | Vector | NDArray The input value.


## Returns

| Vector | NDArray The absolute value.

## Examples

```t
abs(-5)
-- Returns = 5
```

