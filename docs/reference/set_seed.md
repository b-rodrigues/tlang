# set_seed

Set random seed for reproducibility

Initializes the global random number generator with a given seed, making subsequent calls to sample() and slice_sample() deterministic.

## Parameters

- **seed** (`Int`): The seed value.


## Returns



## Examples

```t
set_seed(42)
sample([1, 2, 3, 4, 5], n = 3)
```

## See Also

[slice_sample](slice_sample.html), [sample](sample.html)

