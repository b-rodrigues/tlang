# Property-Based Testing with Popcraft

Comprehensive guide to hardening T code with property-based testing using the **popcraft** package.

## Table of Contents

- [What Is Property-Based Testing?](#what-is-property-based-testing)
- [Audience](#audience)
- [Quick Start](#quick-start)
- [Reproducibility](#reproducibility)
- [Generator Specs](#generator-specs)
- [Generators Reference](#generators-reference)
- [Combinators](#combinators)
- [The Property Contract](#the-property-contract)
- [Shrinking](#shrinking)
- [Finding NA-Handling Bugs](#finding-na-handling-bugs)
- [Integration with Testcraft and `t test`](#integration-with-testcraft-and-t-test)
- [Best Practices](#best-practices)
- [Roadmap](#roadmap)

---

## What Is Property-Based Testing?

Unit tests check a handful of fixed inputs. Property-based testing instead states an **invariant** that must hold for *every* input, then checks it over many randomly generated inputs. When the property fails, the framework reports a minimal (shrunk) counterexample.

The canonical example: R's `prop.test` / Hypothesis / QuickCheck. T's popcraft package brings the same idea to the T language, focused on hardening T's own standard library and user packages.

## Audience

Popcraft is a **language and package-hardening tool** for contributors to T's standard library and for authors of reusable T packages. It is *not* aimed at one-off pipeline authors:

- If you write a data pipeline once, use `assert`, `t check`, and `t diff` — they validate structure and outputs against your declared schema, instantly and without generators.
- If you maintain a package or a library function that many pipelines depend on, add property-based tests with popcraft.

## Quick Start

```t
# Every generated int in [0, 100) is >= 0
set_seed(42)
assert(prop_for_all(prop_gen_int_range(0, 100), \(x) x >= 0))
```

A failing property stops with a shrunk counterexample:

```t
set_seed(42)
assert(prop_for_all(prop_gen_int_range(0, 100), \(x) x < 10, n = 20))
-- Error(AssertionError: Property failed after 1 of 20 runs.
--   counterexample: 72
--   (shrunk): 18
--   predicate: returned false.)
```

`assert(prop_for_all(...))` is the recommended form: it works inside `t test` files, turning a failure into a test failure with the counterexample embedded in the message.

## Reproducibility

All generated values come from a single shared, seedable RNG. Seeding makes the entire run — including any counterexample — bit-for-bit reproducible:

```t
set_seed(7)
a = prop_for_all(prop_gen_int_range(0, 100), \(x) x >= 0, n = 20)
set_seed(7)
b = prop_for_all(prop_gen_int_range(0, 100), \(x) x >= 0, n = 20)
assert(expect_equal(a, b))
```

Always seed at the top of a property test file so failures are reproducible in CI and for whoever debugs them.

### Scoping with `with_seed`

`set_seed` changes the global RNG for the rest of the program. When you only want a *single* reproducible expression — leaving the surrounding stream untouched — use `with_seed(seed, thunk)`:

```t
with_seed(7, \(u) prop_for_all(prop_gen_int_range(0, 100), \(x) x >= 0, n = 20))
```

`with_seed` seeds the RNG for the duration of the thunk, then restores the previous state — even if the thunk raises. It nests, and it works with any RNG consumer (`sample`, `slice_sample`, generators). This is the recommended form inside larger programs where `set_seed` would perturb unrelated draws.

## Generator Specs

Generators are **plain structured `Dict` values** — not closures — so they are inspectable, serializable, and combinable:

```t
g = prop_gen_int_range(1, 5)
g         -- {`gen`: "int_range", `min`: 1, `max`: 5}
```

Because they are data, you can store them in variables, pass them around, and compose them with `prop_map_gen`, `prop_such_that`, and `prop_resize`.

## Generators Reference

| Generator | Signature | Produces |
|-----------|-----------|----------|
| `prop_gen_int` | `prop_gen_int(min = -10, max = 10)` | Random Int in `[min, max]` |
| `prop_gen_int_range` | `prop_gen_int_range(min, max)` | Random Int in `[min, max]` |
| `prop_gen_between` | `prop_gen_between(min, max)` | Random Int in `[min, max]`, **shrinks toward the lower bound** instead of 0 |
| `prop_gen_float_range` | `prop_gen_float_range(min, max)` | Random Float in `[min, max)` |
| `prop_gen_bool` | `prop_gen_bool()` | Random Bool |
| `prop_gen_string_from` | `prop_gen_string_from(chars, min_len, max_len)` | Random String over `chars` (a String, List, or Vector), length in `[min_len, max_len]` |
| `prop_gen_choice` | `prop_gen_choice([g1, g2, ...])` | Uniformly pick one of the given generators |
| `prop_gen_frequency` | `prop_gen_frequency([[w, g], ...])` | Pick a generator weighted by `w` |
| `prop_gen_vector` | `prop_gen_vector(elem_gen, n)` | Vector of `n` draws |
| `prop_gen_list` | `prop_gen_list(elem_gen, n)` | List of `n` draws |
| `prop_gen_factor` | `prop_gen_factor(levels)` | One of the given factor levels |
| `prop_gen_one_of` | `prop_gen_one_of(values)` | Uniformly pick one value from a non-empty List or Vector of values |
| `prop_gen_date_range` | `prop_gen_date_range(start, end)` | Date (or Datetime) drawn uniformly in an inclusive range; bounds must be both Dates or both Datetimes |
| `prop_gen_df` | `prop_gen_df(columns, nrows = 30, na_prob = 0.1)` | DataFrame with generated columns and optional NA injection |
| `prop_gen_df_from` | `prop_gen_df_from(df, nrows = 30, na_prob = 0.1)` | DataFrame matching a sample's columns, with generators inferred from the sample |
| `prop_gen_fn` | `prop_gen_fn(fn)` | Draw a value by calling `fn(size)` with the current generation size |

### `prop_gen_df_from` — schema-derived generators

Instead of hand-writing a `columns` Dict, derive it from a real DataFrame:

```t
mtcars_gen = prop_gen_df_from(mtcars, nrows = 100)
```

Each column's generator is inferred from the non-`NA` sample values: `Int`/`Float` bounds come from the observed min/max (a constant float column falls back to a single-value `one_of`), `String`s are drawn from the observed distinct values, `Factor` columns keep their levels, and `Date`/`Datetime` columns keep their observed range (and timezone). An empty DataFrame, an all-`NA` column, and unsupported column types raise explicit errors.

This is the fastest way to property-test verbs against your own real-world schemas — combine with the row-count invariant:

```t
assert(prop_for_all(
  prop_gen_df_from(mtcars, nrows = 40, na_prob = 0.1),
  \(df) nrow(mutate(df, $z = $mpg * 2)) == nrow(df)))
```

### `prop_gen_fn` — custom generators

For domain-specific generation, wrap any callable: popcraft calls `fn(size)` (with the current generation size, `30` by default and propagated through `prop_resize`):

```t
cube_gen = prop_gen_fn(\(n) n * n * n)
```

`fn` receives the current generation size (`30` by default, propagated through `prop_resize`) and may call other generators, read variables, or draw from the shared RNG — the value it returns is the drawn value.

### `prop_gen_between` — in-domain shrinking

For properties where the domain has a natural lower bound (e.g., "the value must be ≥ 100"), use `prop_gen_between(min, max)`. Draws are identical to `prop_gen_int_range(min, max)`, but shrinking pushes values toward the lower bound rather than toward 0:

```t
set_seed(42)
prop_for_all(prop_gen_between(100, 200), \(x) x <= 100, n = 20)
-- counterexample: 154 (shrunk): 101
```

Without `prop_gen_between`, the same test with `prop_gen_int_range` would shrink the counterexample toward 0 — potentially below the meaningful domain. Column generators inside `prop_gen_df` shrink toward the column's lower bound.

**Shrinker scope:** Generator-aware shrinking applies only at the top level and for DataFrame columns. Inside composite generators (list, vector, choice, frequency), values shrink toward the standard canonical floors (0, 0.0, false, "") regardless of the element's generator spec.

### `prop_show_spec` — introspection

Render any generator spec back to valid T source. Useful for debugging generative pipelines, logging, and verifying composition:

```t
prop_show_spec(prop_gen_df([x: prop_gen_between(1, 5), s: prop_gen_one_of(["a", "b"])], nrows = 3))
-- "prop_gen_df([x: prop_gen_between(1, 5), s: prop_gen_one_of([\"a\", \"b\"])], nrows = 3, na_prob = 0.)"
```

The rendered output is behaviorally equivalent to the original: same seed produces identical draws. Closure-based generators (`map`, `such_that`, `fn`) produce explicit errors since they capture callables that cannot be serialized. The output is intended for debugging and reproducibility, not serialization of arbitrary closures.

### Named properties: `prop_named` + `prop_test`

Instead of repeating the same predicate with different generators inline, build a **named property** and reuse it:

```t
m = prop_named("mutate_preserves_nrow", \(df) nrow(mutate(df, $z = $x * 2)) == nrow(df))
set_seed(1)
prop_test(m, prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 40, na_prob = 0.2), n = 25)
prop_test(m, prop_gen_df([x: prop_gen_int_range(0, 100)], nrows = 40, na_prob = 0.2), n = 25)
```

Named properties are plain immutable Dicts (`{name, property}`) — no global registry. Failure reports prefix the property name:

```
STOP(Property mutate_preserves_nrow failed after 1 of 25 runs.
  counterexample: DataFrame(...)
  ...)
```

### `shrink_verify` — opt-in exhaustive shrinking

By default, the greedy shrinker caps per-level candidate lists at 32 for performance. This is sufficient for most workloads. When shrinking a deeply nested value (large Dict or DataFrame) and the reported counterexample seems suspiciously large, opt in to exhaustive verification:

```t
prop_for_all(gen, predicate, n = 20, shrink_verify = true)
prop_test(named, gen, n = 20, shrink_verify = true)
```

With `shrink_verify = true`, every candidate at the shrink fixpoint is re-verified without the 32-cap, ensuring the reported counterexample is truly minimal. Accepts `Bool` only; defaults to `false`. **May substantially increase shrinking time for large nested structures.**

### `prop_stats` — probing a generator

To sanity-check a generator without writing a property, probe it:

```t
prop_stats(prop_gen_df_from(mtcars, nrows = 50), n = 20)
-- {`n_runs`: 20, `n_errors`: 0, `value_types`: {`DataFrame`: 20},
--  `nested_sizes`: {`df`: [1, 2, ..., 20]}, `elapsed_ms`: ...}
```

`prop_stats(gen, n = 100)` ramps the generation size from `1` to `n` and returns a `Dict` with `n_runs`, `n_errors`, `value_types` (per-type counts), `nested_sizes` (observed Vector/List/DataFrame lengths), and `elapsed_ms`. A high `n_errors` means the generator is malformed for some sizes.

### `prop_gen_df` and NA injection

`columns` is a Dict mapping column names to generators, e.g.:

```t
df_gen = prop_gen_df(
  [x: prop_gen_float_range(0.0, 100.0),
   grp: prop_gen_factor(["a", "b"]),
   n: prop_gen_int_range(1, 10)],
  nrows = 40,
  na_prob = 0.1)
```

`na_prob` injects typed `NA` values (`NAInt`/`NAFloat`/`NABool`/`NAString` matching the column's generator) into the columns. This is the single most effective way to catch verbs that mishandle missingness.

## Combinators

| Function | Purpose |
|----------|---------|
| `prop_map_gen(source, fn)` | Draw a value from `source`, apply `fn`, yield the result |
| `prop_such_that(source, pred, max_tries = 100)` | Keep drawing until `pred` holds; fails after `max_tries` |
| `prop_resize(source, n)` | Override the size of nested `df`/`list`/`vector` generators to `n` |

Example — generate only even numbers:

```t
even_gen = prop_such_that(prop_gen_int_range(1, 10), \(x) x % 2 == 0)
```

## The Property Contract

`prop_for_all` draws `n` values (default `100`) and evaluates the property on each. The property result is classified:

| Property returns | Meaning |
|------------------|---------|
| `true` | Pass — continue |
| `false` | Fail — report counterexample |
| `Expect_pass` | Pass — continue |
| `Expect_stop msg` / `Expect_hold msg` | Fail — report counterexample with the message |
| `Error` | Fail — report counterexample with the raised error text |
| `NA` | Fail — "property must handle missingness explicitly" |
| anything else | Fail — "expected Bool or an Expect value" |

By default `prop_for_all` stops at the first failure. Pass `max_counterexamples = k` to collect up to `k` render-distinct failing inputs (each shrunk) and report them as numbered blocks:

```t
set_seed(42)
prop_for_all(prop_gen_int_range(0, 100), \(x) x < 10, n = 20, max_counterexamples = 3)
-- Expect_stop: Property failed after 3 of 20 runs (showing 3 counterexamples).
--   counterexample #1: 54
--   (shrunk): 13
--   predicate: returned false
--   counterexample #2: 91
--   ...
```

The `NA` rule is deliberate (see the *Death to Null* policy): generated frames may contain `NA`, and a property that cannot handle it must say so rather than silently pass.

## Shrinking

When a property fails, popcraft attempts to find a **smaller input that still fails**, then reports both the original counterexample and the shrunk one:

- Ints shrink toward `0` by halving.
- Floats shrink toward `0`.
- Strings shrink by trimming characters.
- Lists/Vectors shrink by truncating prefixes and shrinking elements.
- Dicts shrink field-by-field.
- DataFrames shrink by halving the row count (down to the empty frame) and then minimizing individual cells to canonical values derived from each column's type (`Int` → `0`, `Float` → `0.0`, `Bool` → `false`, `String` → `""`, `Factor` → first level). `NA` cells are left untouched.

Shrinking is deterministic and only affects the **message** — it never changes whether a run passes or fails. Pass `shrink = false` to `prop_for_all` to disable it.

## Finding NA-Handling Bugs

The classic bug class for data verbs: a verb that silently drops rows when an `NA` flows through it. Property-based tests catch it instantly:

```t
set_seed(7)
assert(prop_for_all(
  prop_gen_df(
    [x: prop_gen_float_range(0.0, 100.0),
     grp: prop_gen_factor(["a", "b"])],
    nrows = 40,
    na_prob = 0.1),
  \(df) nrow(mutate(df, $z = $x * 2)) == nrow(df)))
```

If `mutate` ever drops rows on NA input, this property fails with a DataFrame counterexample showing the injected `NA(Float)` values.

Other invariants worth testing:

```t
# filter never returns more rows than it started with
assert(prop_for_all(
  prop_gen_df([x: prop_gen_float_range(-10.0, 10.0)], nrows = 30, na_prob = 0.1),
  \(df) nrow(filter(df, $x > 0)) <= nrow(df)))

# arrange is a stable permutation (row counts preserved)
assert(prop_for_all(
  prop_gen_df([k: prop_gen_int_range(1, 100), v: prop_gen_string_from("ab", 0, 4)],
              nrows = 50, na_prob = 0.1),
  \(df) nrow(arrange(df, $k)) == nrow(df)))
```

## Integration with Testcraft and `t test`

`prop_for_all` returns an `Expect` value, so it composes with the testcraft package and with `t test`:

```t
-- testfile.t — run with: t test testfile.t
set_seed(42)

test("ints stay in range", function() {
  assert(prop_for_all(prop_gen_int_range(-100, 100), \(x) x >= -100 && x <= 100))
})

test("nrow is stable under mutate", function() {
  assert(prop_for_all(
    prop_gen_df([x: prop_gen_float_range(0.0, 10.0)], nrows = 20, na_prob = 0.1),
    \(df) nrow(mutate(df, $y = $x + 1)) == nrow(df)))
})
```

## Best Practices

1. **Always `set_seed` first.** Without it, a failure that appears locally may not reproduce later.
2. **Prefer `assert(prop_for_all(...))`** over capturing the value, so failures carry the counterexample into the assertion message.
3. **Use `na_prob` in DataFrame generators.** Missingness is where most verbs break.
4. **Keep properties small and invariant-shaped.** "row count unchanged", "output length equals input length", "no NA in output" are the most valuable.
5. **Combine `prop_for_all` with `expect_*`** for readable diagnostics: `assert(prop_for_all(g, \(x) expect_equal(f(x), f(x))))`-style compositions.
6. **Do not hand-wave error cases.** A property returning an `Error` fails loudly — if you *expect* an error for some inputs, handle it explicitly inside the property.
7. **For one-off pipelines, don't reach for popcraft.** Use `assert`, `t check`, and `t diff`.

## Roadmap

- **v2 — shipped**: `prop_gen_df_from(df)` schema-driven generators derived from a sample DataFrame; custom generators via `prop_gen_fn`; `prop_gen_one_of`, `prop_gen_date_range`, `prop_gen_df_from`, `prop_gen_fn`, and `prop_stats`.
- **v3 — shipped**: `prop_gen_between(min, max)` in-domain shrinking; `prop_show_spec(spec)` generator introspection (render to T source); `prop_named(name, property)` + `prop_test(named, gen, ...)` named reusable properties with shrink-verified invariants; `shrink_verify = true` opt-in exhaustive shrink re-verification.
