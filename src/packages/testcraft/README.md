# testcraft

Lightweight unit-testing primitives, inspired by R's `testthat`.

Comparisons don't raise directly — `expect_equal()` returns a `VExpect`
value (`Expect_pass`, `Expect_stop`, or `Expect_hold`) describing the
outcome, so it can be inspected, combined, or passed straight to `assert()`.

| Kind | Meaning | Truthy |
|---|---|---|
| `Expect_pass` | values matched | yes |
| `Expect_stop msg` | values differed; `msg` explains how | no |
| `Expect_hold msg` | comparison involved NA; `msg` explains | no |

## Functions

### Core

| Function | Description |
|----------|-------------|
| `expect_equal(actual, expected, tolerance = 1e-9)` | Compare two values, returning an Expect value |
| `expect_pass(x)` | `true` if `x` is a passing Expect value |
| `expect_fail(x)` | `true` if `x` is a stopping or holding Expect value |
| `expect_msg(x)` | The Stop/Hold message of a failing Expect value |

### Numeric relations

| Function | Description |
|----------|-------------|
| `expect_lt(a, b)` | Pass if `a < b` (numeric only) |
| `expect_lte(a, b)` | Pass if `a <= b` (numeric only) |
| `expect_gt(a, b)` | Pass if `a > b` (numeric only) |
| `expect_gte(a, b)` | Pass if `a >= b` (numeric only) |

### Type, truth, and behaviour

| Function | Description |
|----------|-------------|
| `expect_true(x)` | Pass only if `x` is `VBool true` |
| `expect_false(x)` | Pass only if `x` is `VBool false` |
| `expect_truthy(x)` | Pass if `x` is truthy (`is_truthy`) |
| `expect_falsy(x)` | Pass if `x` is falsy |
| `expect_type(x, t)` | Pass if `type_name(x) == t` |
| `expect_error(expr, class = "", message = "")` | Pass if `expr` is an error; optional class/message checks |
| `expect_length(x, n)` | Pass if length/size/row-count of `x` equals `n` |

### Data frames and collections

| Function | Description |
|----------|-------------|
| `expect_nrow(df, n)` | Pass if DataFrame has exactly `n` rows |
| `expect_ncol(df, n)` | Pass if DataFrame has exactly `n` columns |
| `expect_colnames(df, names)` | Pass if DataFrame columns match `names` |
| `expect_fields(x, names)` | Pass if Dict keys or List labels match `names` |
| `expect_in(x, values)` | Pass if `x` (or every element of `x`) is in `values` |

### Pipeline node diagnostics

| Function | Description |
|----------|-------------|
| `expect_warning(node, kind = "", message = "")` | Pass if node produced a warning; optionally match `kind` and/or regex on `message` |

`assert()` understands `VExpect` directly: on `Expect_pass` it returns
`true`, on `Expect_stop`/`Expect_hold` it raises an `AssertionError` using
the comparison's own diagnostic message.

## Examples

```t
assert(expect_equal(1, 1))
assert(expect_equal(0.1 + 0.2, 0.3, tolerance = 1e-9))

-- inspecting expect values
expect_pass(expect_equal(1, 1))     -- true
expect_fail(expect_equal(1, 2))     -- true
expect_msg(expect_equal(1, 2))      -- "`1` != `2`"

-- relational
assert(expect_lt(1, 2))
assert(expect_gte(5, 5))

-- truth / type
assert(expect_true(true))
assert(expect_truthy(42))
assert(expect_type("hello", "String"))

-- error checking
assert(expect_error(error("boom"), class = "RuntimeError"))
assert(expect_error(error("invalid"), message = "invalid"))

-- data frames
df = to_dataframe(col1 = 1:3, col2 = 4:6)
assert(expect_nrow(df, 3))
assert(expect_ncol(df, 2))
assert(expect_colnames(df, ["col1", "col2"]))

-- membership
assert(expect_in(3, 1:5))
```

`expect_equal` compares DataFrames, Vectors, and Lists element-wise and
reports the location of the first difference (e.g. which column/row, or
which vector index, differs) rather than dumping the whole value.

## Status

Built-in package — included with T by default.
