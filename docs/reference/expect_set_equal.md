# expect_set_equal

Order-independent set equality assertion

Passes if two Lists or Vectors contain the exact same unique elements regardless of order.

## Parameters

- **list1** (`List`): | Vector First collection.

- **list2** (`List`): | Vector Second collection.


## Returns

`Expect_pass` when sets match; `Expect_hold` on NA; `Expect_stop` if elements differ.

## Examples

```t
assert(expect_set_equal([1, 2, 3], [3, 2, 1]))
```

## See Also

[expect_in](expect_in.html), [expect_equal](expect_equal.html)

