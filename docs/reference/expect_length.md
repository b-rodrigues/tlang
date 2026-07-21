# expect_length

Container length assertion

Passes if the length/size/row-count of `x` equals `n`. Supports Vector, List, String, DataFrame (row count), and Dict (entry count).

## Parameters

- **x** (`Vector`): | List | String | DataFrame | Dict The container to measure.

- **n** (`Int`): Expected length.


## Returns

`Expect_pass` when length matches; `Expect_hold` on NA; `Expect_stop` on errors or mismatch.

## Examples

```t
assert(expect_length([1, 2, 3], 3))
assert(expect_length("hello", 5))
```

## See Also

[expect_ncol](expect_ncol.html), [expect_nrow](expect_nrow.html)

