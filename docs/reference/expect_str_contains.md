# expect_str_contains

Substring search assertion

Passes if the actual String contains the specified substring.

## Parameters

- **actual** (`String`): The string value to inspect.

- **substring** (`String`): Substring to search for.


## Returns

`Expect_pass` when found; `Expect_hold` on NA; `Expect_stop` if missing.

## Examples

```t
assert(expect_str_contains("hello world", "world"))
```

## See Also

[expect_match](expect_match.html)

