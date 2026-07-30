# Implement testcraft Package

Create a new `testcraft` package inspired by R's `testthat`, starting with `expect_equal()` as the anchor.

## Design: VExpect value type

Rather than returning raw booleans or errors, `expect_equal` returns a new value variant `VExpect` with one of three states:

| Kind | Meaning | Truthy |
|---|---|---|
| `Expect_pass` | values matched | yes |
| `Expect_stop msg` | values differed, `msg` explains how | no |
| `Expect_hold msg` | comparison involved NA, `msg` explains | no |

This means `VExpect` values can be used directly with `if`, `assert`, and in pipeline conditions. The `assert` function in `t_assert.ml` is updated to understand `VExpect`: on `Expect_pass` it returns `VBool true`, on `Expect_stop`/`Expect_hold` it extracts the message and produces a descriptive `AssertionError`.

## Files to modify

### 1. `src/ast.ml` — Add VExpect variant

- Add `expect_kind` type after `intent_block` (~line 90):
  ```ocaml
  and expect_kind =
    | Expect_pass
    | Expect_stop of string
    | Expect_hold of string
  ```
- Add `VExpect of expect_kind` to the `value` type (after `VNodeResult`, ~line 284)
- Update `is_truthy` (~line 600):
  ```ocaml
  | VExpect Expect_pass -> true
  | VExpect (Expect_stop _ | Expect_hold _) -> false
  ```
- Update `type_name` (~line 790): add `| VExpect _ -> "Expect"`
- Update `value_to_string` (~line 1095): render `PASS` / `STOP(msg)` / `HOLD(msg)`

### 2. `src/repl.ml` — Update `value_summary`

Add `VExpect` rendering (alongside the VIntent case, ~line 274).

### 3. `src/packages/testcraft/t_expect_equal.ml` — Create

Core `expect_equal(actual, expected, tolerance = 0.0)` function.

**Comparison logic**:
- If either arg is `VError` → `Expect_stop("`actual/expected` is an error: ...")`
- If either arg is `VNA _` → `Expect_hold("`actual/expected` is NA")`
- Same-type comparisons:
  - `VInt, VInt`: exact equality
  - `VFloat, VFloat`: `abs(a - b) < tolerance` (default `1e-9`)
  - Cross numeric (`VInt`/`VFloat`): promote to float, check tolerance
  - `VBool, VBool`: direct
  - `VString, VString`: direct
  - `VDate, VDate`: direct
  - `VDatetime, VDatetime`: direct (includes micros + tz)
  - `VFactor, VString`: extract level, compare
  - `VFactor, VFactor`: compare indexed level
  - `VDataFrame, VDataFrame`: use `Utils.dataframe_equal`
  - `VVector, VVector`: element-wise with path reporting for first diff
  - `VList, VList`: pairwise with label reporting
  - Other same-type: OCaml structural `=`
- Different types: `Expect_stop("`actual` (type) != `expected` (type)")`

**Diagnostics messages** follow the pattern of R's testthat:
- `Stop("`a` != `b`")` for scalars
- `Stop("`a` (Int) != `b` (String)")` for type mismatch
- `Stop("DataFrame: column `x` differs at row 3: `5` != `3`")` for DataFrame diffs
- `Stop("Vector: element at index 2 differs: `7` != `8`")` for vector element diffs
- `Hold("`actual` is NA, cannot compare `actual` != `expected`")` for NA
- `Hold("`expected` is NA, cannot compare `actual` != `expected`")` for expected NA

### 4. `src/packages/testcraft/t_expect_pass.ml` — Create

```ocaml
expect_pass(x) — returns VBool true if x is VExpect Expect_pass
```

Used for explicit checking:
```t
assert(expect_pass(expect_equal(a, b)))   # assert with explicit pass check
```

### 5. `src/packages/testcraft/t_expect_fail.ml` — Create

```ocaml
expect_fail(x) — returns VBool true if x is VExpect Expect_stop or Expect_hold
```

### 6. `src/packages/testcraft/t_expect_msg.ml` — Create

```ocaml
expect_msg(x) — returns VString of the Stop/Hold message, or VError if x is not a failure
```

### 7. `src/packages/testcraft/README.md` — Create

Following the style of `colcraft/README.md` and `strcraft/README.md`.

### 8. `src/dune` — Register modules

Add under a new `; packages/testcraft` comment:
```
t_expect_equal t_expect_pass t_expect_fail t_expect_msg
```

### 9. `src/packages/core/packages.ml` — Register package

- Add `let testcraft_package = { name = "testcraft"; ... }`
- Add `"testcraft"` to `package_families` match arm
- Add `testcraft_package` to `all_packages`
- Add register calls in `init_env()`:
  ```ocaml
  let env = T_expect_equal.register env in
  let env = T_expect_pass.register env in
  let env = T_expect_fail.register env in
  let env = T_expect_msg.register env in
  ```

### 10. `src/packages/base/t_assert.ml` — Update assert for VExpect

Extend the `assert` function so that when given a `VExpect`:
- `Expect_pass` → `VBool true` (passes)
- `Expect_stop msg` → `AssertionError` with the msg
- `Expect_hold msg` → `AssertionError` with the msg

This makes `assert(expect_equal(a, b))` the standard usage pattern.

### 11. `summary.md` — Add entry

Add testcraft package to the relevant section.

### 12. `docs/api-reference.md` — Add testcraft section

Add function signatures, parameters, return types, and examples.

## Unit tests

Create `tests/unit/test_expect_equal.ml` covering:

- `expect_equal(1, 1)` → `Expect_pass`
- `expect_equal(1, 2)` → `Expect_stop "1 != 2"`
- `expect_equal(1.0, 1.0)` → `Expect_pass`
- `expect_equal(0.1 + 0.2, 0.3, tolerance = 1e-9)` → `Expect_pass`
- `expect_equal(1.0, 2.0)` → `Expect_stop`
- `expect_equal("a", "a")` → `Expect_pass`
- `expect_equal("a", "b")` → `Expect_stop`
- `expect_equal(NA, 1)` → `Expect_hold`
- `expect_equal(1, NA)` → `Expect_hold`
- `expect_equal(VError, 1)` → `Expect_stop`
- `expect_equal(1, VError)` → `Expect_stop`
- `expect_equal(1, "1")` → `Expect_stop` (type mismatch)
- `expect_equal(true, true)` → `Expect_pass`
- `assert(expect_equal(1, 1))` → `VBool true`
- `assert(expect_equal(1, 2))` → `VError AssertionError`

## Golden tests (T vs R)

No R comparison needed. Use unit tests to verify correctness.

## Implementation order

1. `src/ast.ml` — add `expect_kind` type and `VExpect` variant + all match updates
2. `src/repl.ml` — add `value_summary` case
3. `src/packages/testcraft/t_expect_equal.ml` — core implementation
4. `src/packages/testcraft/t_expect_pass.ml`
5. `src/packages/testcraft/t_expect_fail.ml`
6. `src/packages/testcraft/t_expect_msg.ml`
7. `src/packages/testcraft/README.md`
8. `src/dune` — module registration
9. `src/packages/core/packages.ml` — package metadata + init_env
10. `src/packages/base/t_assert.ml` — VExpect handling in assert
11. `summary.md` — entry
12. `docs/api-reference.md` — documentation
13. `tests/unit/test_expect_equal.ml` — unit tests
14. Tests → `dune runtest` → fix
15. `git add` + commit
