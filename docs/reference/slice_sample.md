# slice_sample

Randomly sample rows from a DataFrame

Draws a random sample of n rows from a DataFrame, with or without replacement.

## Parameters

- **data** (`DataFrame`): The input DataFrame.

- **n** (`Int`): = 1 Number of rows to sample.

- **replace** (`Bool`): = false Sample with replacement.


## Returns

A DataFrame containing the sampled rows.

## Examples

```t
mtcars |> slice_sample(n = 5)
mtcars |> slice_sample(n = 100, replace = true)
```

## See Also

[slice_min](slice_min.html), [slice_max](slice_max.html), [slice](slice.html), [set_seed](set_seed.html), [sample](sample.html)

