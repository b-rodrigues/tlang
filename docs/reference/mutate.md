# mutate

Mutate DataFrame

Adds new columns or modifies existing ones.

## Parameters

- **df** (`DataFrame`): The input DataFrame.

- **...** (`Expressions`): Key-value pairs of new columns.


## Returns

The mutated DataFrame.

## Examples

```t
mutate(mtcars, $ratio = $mpg / $hp)
```

## See Also

[select](select.html), [summarize](summarize.html)

