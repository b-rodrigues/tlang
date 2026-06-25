# sample

Random sample from a vector or list

Draws a random sample of size n from a vector or list, with or without replacement.

## Parameters

- **x** (`Vector`): | List The input data.

- **n** (`Int`): = 1 Sample size.

- **replace** (`Bool`): = false Sample with replacement.


## Returns

| List The random sample.

## Examples

```t
sample([1, 2, 3, 4, 5], n = 3)
sample([1, 2, 3], n = 5, replace = true)
```

## See Also

[slice_sample](slice_sample.html), [set_seed](set_seed.html)

