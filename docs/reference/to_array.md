# to_array

Convert to NDArray

Converts numeric columns of a DataFrame to a matrix (NDArray).

## Parameters

- **df** (`DataFrame`): The input DataFrame.

- **cols** (`List[Symbol|String]`): (Optional) Columns to include. Defaults to all numeric.


## Returns

A 2D array of the data.

## Examples

```t
mat = to_array(mtcars)
mat = to_array(mtcars, [$mpg, $wt])
```

## See Also

[dataframe](dataframe.html)

