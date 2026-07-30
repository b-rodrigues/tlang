# expect_fields

Dict key / named List label assertion

Passes if a Dict's keys or a named List's labels match the given list of strings exactly (order-sensitive).

## Parameters

- **x** (`Dict`): | List The Dict or named List to inspect.

- **names** (`List`): | Vector A list or vector of expected field name strings.


## Returns

`Expect_pass` when fields match; `Expect_hold` on NA; `Expect_stop` on errors or mismatch.

## Examples

```t
assert(expect_fields([a: 1, b = 2], ["a", "b"]))
```

## See Also

[expect_in](expect_in.html), [expect_colnames](expect_colnames.html)

