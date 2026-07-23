# expect_match

Regex string match assertion

Passes if the actual String matches the given regular expression pattern.

## Parameters

- **actual** (`String`): The string value to inspect.

- **pattern** (`String`): Regular expression pattern string.


## Returns

`Expect_pass` when matching; `Expect_hold` on NA; `Expect_stop` on mismatch or invalid pattern.

## Examples

```t
assert(expect_match("user@example.com", ".*@.*"))
```

## See Also

[expect_type](expect_type.html), [expect_str_contains](expect_str_contains.html)

