# expect_unique

Element uniqueness assertion

Passes if all elements in a Vector, List, or DataFrame are distinct. Returns `Expect_stop` detailing duplicate values if any are found.

## Parameters

- **x** (`Vector`): | List | DataFrame The container or vector to check for uniqueness.


## Returns

`Expect_pass` if all elements are unique; `Expect_hold` on NA; `Expect_stop` if duplicates exist.

## Examples

```t
assert(expect_unique([1, 2, 3, 4]))
assert(expect_unique(df.$id))
```

## See Also

[expect_equal](expect_equal.html), [expect_in](expect_in.html), [expect_length](expect_length.html)

