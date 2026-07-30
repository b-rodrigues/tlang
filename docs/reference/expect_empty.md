# expect_empty

Empty container / string assertion

Passes if a List, Dict, Vector, String, or DataFrame is empty (0 elements/rows/length).

## Parameters

- **actual** (`List`): | Dict | Vector | String | DataFrame The container to check.


## Returns

`Expect_pass` when empty; `Expect_hold` on NA; `Expect_stop` if non-empty.

## Examples

```t
assert(expect_empty([]))
```

## See Also

[expect_nrow](expect_nrow.html), [expect_length](expect_length.html)

