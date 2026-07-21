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

| Function | Description |
|----------|-------------|
| `expect_equal(actual, expected, tolerance = 1e-9)` | Compare two values, returning an Expect value |
| `expect_pass(x)` | `true` if `x` is a passing Expect value |
| `expect_fail(x)` | `true` if `x` is a stopping or holding Expect value |
| `expect_msg(x)` | The Stop/Hold message of a failing Expect value |

`assert()` understands `VExpect` directly: on `Expect_pass` it returns
`true`, on `Expect_stop`/`Expect_hold` it raises an `AssertionError` using
the comparison's own diagnostic message.

## Examples

```t
assert(expect_equal(1, 1))
assert(expect_equal(0.1 + 0.2, 0.3, tolerance = 1e-9))

-- explicit checks
expect_pass(expect_equal(1, 1))     -- true
expect_fail(expect_equal(1, 2))     -- true
expect_msg(expect_equal(1, 2))      -- "`1` != `2`"

-- a failing comparison, asserted directly
assert(expect_equal(1, 2))
-- AssertionError: Assertion failed: `1` != `2`.
```

`expect_equal` compares DataFrames, Vectors, and Lists element-wise and
reports the location of the first difference (e.g. which column/row, or
which vector index, differs) rather than dumping the whole value.

## Status

Built-in package — included with T by default.
