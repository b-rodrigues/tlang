# expect_type

Type name assertion

Passes if the runtime type name of `x` matches the given string (e.g. `"Int"`, `"String"`, `"DataFrame"`).

## Parameters

- **x** (`Any`): The value to inspect.

- **type_name** (`String`): Expected type name.


## Returns

`Expect_pass` when types match; `Expect_hold` on NA; `Expect_stop` on errors or type mismatch.

## Examples

```t
assert(expect_type(42, "Int"))
assert(expect_type("hello", "String"))
```

## See Also

[expect_error](expect_error.html), [expect_true](expect_true.html)

