# Property Testing Cookbook

How to think in property-testing terms when hardening T's standard library and your own packages. Assumes familiarity with
`prop_for_all`, generators, and the concepts from `docs/property-testing.md`.

---

## Table of Contents

- [The mental model](#the-mental-model)
- [Pattern 1: Round-trip](#pattern-1-round-trip)
- [Pattern 2: Idempotence](#pattern-2-idempotence)
- [Pattern 3: Bounds and ranges](#pattern-3-bounds-and-ranges)
- [Pattern 4: Algebraic identities](#pattern-4-algebraic-identities)
- [Pattern 5: Row-count invariants](#pattern-5-row-count-invariants)
- [Pattern 6: NA hardening](#pattern-6-na-hardening)
- [Pattern 7: Named properties](#pattern-7-named-properties)
- [Writing your first property test](#writing-your-first-property-test)

---

## The mental model

A property test answers one question: **"What is always true about this function, for every possible input?"**

Examples of good properties:

| Function | Property | Why |
|----------|----------|-----|
| `str_split` + `str_join` | `str_join(str_split(s, sep), sep) == s` | Round-trip — encode then decode should recover original |
| `to_lower` | `to_lower(to_lower(s)) == to_lower(s)` | Idempotence — applying twice is the same as once |
| `sd` | `sd(x) >= 0` | Bounds — standard deviation is never negative |
| `sqrt` | `sqrt(x * x) == abs(x)` | Algebraic identity — follows from definition |
| `filter` | `nrow(filter(df, $x > k)) <= nrow(df)` | Monotonicity — filter never adds rows |

Bad property: `mean(x)` equals 25.3 for x in [0, 100]. This is a **fixed-case test**, not a property — it only checks one scenario and tells you nothing about the function's behavior for other inputs.

---

## Pattern 1: Round-trip

**Encode then decode should recover the original.** Works for serialization, string splitting, type conversion, and any invertible operation.

```t
-- strings
prop_named("split_join", \(s) s == "" || str_join(str_split(s, ","), ",") == s)

-- numeric conversion
prop_named("int_float", \(x) to_integer(to_float(x)) == x)

-- dates: format then parse recovers the original date
prop_named("format_roundtrip", \(d) parse_date(format_date(d, "%Y-%m-%d"), "%Y-%m-%d") == d)

-- dates: period arithmetic is invertible
prop_named("period_roundtrip", \(d) (d + make_period(days = 5)) - d == make_period(days = 5))
```

**Generator tips:**
- For strings, `prop_gen_string_from("abc,", 0, 12)` provides strings that may contain the split delimiter
- Guard against empty inputs where the operation is lossy (`""` → `[""]` → `""`, but `str_split("a", ",") |> str_join(",")` works)
- For date round-trips, `prop_gen_ymd(2000, 2024)` draws real calendar days across a 25-year span

**When to use:** strcraft (split/join, extract/replace), core (serialize/deserialize, to_X conversions), dataframe I/O (write_csv → read_csv), chrono (format/parse, ymd, period arithmetic).

---

## Pattern 2: Idempotence

**Applying the operation twice is the same as applying it once.** Catches state leakage and side effects.

```t
-- case conversion
prop_named("lower_idem", \(s) to_lower(to_lower(s)) == to_lower(s))
prop_named("upper_idem", \(s) to_upper(to_upper(s)) == to_upper(s))

-- trimming
prop_named("trim_idem",  \(s) str_trim(str_trim(s)) == str_trim(s))
```

**Generator:** `prop_gen_string_from("abcdefgh", 0, 12)` — alphabetic characters, no digits or punctuation that might confuse case operations.

**When to use:** strcraft (trim, pad, case conversions), core (clean_colnames, normalize), colcraft (distinct, arrange).

---

## Pattern 3: Bounds and ranges

**Output always falls within a predictable range.** The simplest and most reliable property.

```t
-- tanh always in [-1, 1]
prop_named("tanh_range", \(x) tanh(x) >= -1.0 && tanh(x) <= 1.0)

-- sqrt of non-negative is non-negative
prop_named("sqrt_nonneg", \(x) x < 0.0 || sqrt(x) >= 0.0)

-- abs never negative
prop_named("abs_nonneg", \(x) abs(x) >= 0.0)
```

**Generator:** `prop_gen_float_range(-100.0, 100.0)` for continuous functions, `prop_gen_int_range(-100, 100)` for integer-only operations.

**Date bounds:** `prop_gen_ymd(min_year, max_year)` draws calendar days uniformly across the year range, and counterexamples shrink to `Date(min_year-01-01)` (staying in-domain). Use it for chrono invariants:

```t
-- day-of-month always within the month's real length
prop_named("day_bound", \(d) day(d) >= 1 && day(d) <= days_in_month(year(d), month(d)))

-- leap-year flag consistent with February's length
prop_named("leap_consistent", \(d) is_leap_year(year(d)) == (days_in_month(year(d), 2) == 29))

-- weekday always in [1, 7]
prop_named("wday_bound", \(d) wday(d) >= 1 && wday(d) <= 7)
```

**When to use:** math (all trig/hyperbolic/exp functions), stats (sd ≥ 0, cor in [-1, 1]), core (length ≥ 0, ncol ≥ 0, nrow ≥ 0), chrono (date-part bounds).

---

## Pattern 4: Algebraic identities

**Two different computations give the same result.** Catches implementation errors in fundamental operations.

```t
-- sin² + cos² = 1
prop_named("sin_cos", \(x) abs((sin(x) * sin(x) + cos(x) * cos(x)) - 1.0) < 0.0001)

-- log(exp(x)) ≈ x
prop_named("log_exp", \(x) abs(log(exp(x)) - x) < 0.0001)

-- sign(x) * abs(x) == x
prop_named("sign_abs", \(x) sign(x) * abs(x) == x)
```

**Important:** Use approximate equality (`abs(a - b) < 0.0001`) for floating-point identities. Never use `==` on floats in invariant properties.

**Generator tip:** Restrict ranges for identities that diverge numerically:
- `exp(log(x))` needs `x > 0` — use `prop_gen_float_range(0.0, 100.0)`
- `log(exp(x))` fails for large `x` — use `prop_gen_float_range(-10.0, 10.0)`

---

## Pattern 5: Row-count invariants

**DataFrame row count follows predictable algebra.** The workhorse for hardening colcraft verbs.

```t
-- mutate never changes nrow
prop_named("mutate_nrow", \(df) nrow(mutate(df, $z = $x * 2)) == nrow(df))

-- filter never adds rows
prop_named("filter_leq",  \(df) nrow(filter(df, $x > 50)) <= nrow(df))

-- group sizes sum to total
prop_named("group_sum",   \(df) to_integer(sum((df |> group_by($g) |> summarize($cnt = n())).cnt)) == nrow(df))
```

**Generator:** `prop_gen_df([x: gen, g: factor_gen], nrows = 40, na_prob = 0.2)` — multiple columns with NA injection.

**When to use:** Every colcraft verb (mutate, arrange, filter, group_by, summarize, select, rename, distinct, head, slice_sample, fill, bind_rows, bind_cols, left_join, anti_join, etc.).

---

## Pattern 6: NA hardening

**Functions don't silently corrupt or crash on NA input.** The single highest-value use of `prop_gen_df` — inject NAs and check that invariants still hold.

```t
-- mutate preserves nrow even with NAs
prop_named("mutate_na", \(df) nrow(mutate(df, $z = $x * 2)) == nrow(df))

prop_test(mutate_na,
  prop_gen_df([x: prop_gen_float_range(0.0, 100.0), g: prop_gen_factor(["a", "b"])],
               nrows = 40, na_prob = 0.3))
```

The property itself is the same as without NAs — the `na_prob` in the generator does the work. If `mutate` drops rows with NA or fails to propagate NAs correctly, the row count invariant fails and you get a shrunk counterexample DataFrame showing exactly which column had NAs.

**Recommended `na_prob`:** Start with `0.1` (10% missing) for broad coverage. Increase to `0.3`-`0.5` for stress-testing NA-heavy paths. Use `1.0` for checking that functions handle all-NA inputs correctly.

---

## Pattern 7: Named properties

**Define properties once, test against many generators.** Use `prop_named` + `prop_test` instead of repeating `prop_for_all` with the same predicate.

```t
m = prop_named("mutate_preserves_nrow", \(df) nrow(mutate(df, $z = $x * 2)) == nrow(df))

-- test against float columns
prop_test(m, prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 40, na_prob = 0.2))

-- test against int columns
prop_test(m, prop_gen_df([x: prop_gen_int_range(0, 100)], nrows = 40, na_prob = 0.2))

-- test against schema-derived generators
prop_test(m, prop_gen_df_from(mtcars, nrows = 40, na_prob = 0.2))
```

The property lives in one place. Adding a new generator is one line. If the verb breaks, the macro name appears in the failure: `STOP(Property mutate_preserves_nrow failed...)`.

---

## Writing your first property test

1. **Pick a function** — start with something simple and pure (math function, string operation).

2. **State the invariant** — what is always true? Write it as a lambda.

3. **Choose a generator** — what domain produces valid inputs? e.g. `prop_gen_float_range(0, 100)` for positive-only functions, `prop_gen_int_range(-100, 100)` for general integers.

4. **Pick a reasonable `n`** — 30 for fast CI, 100 for thorough local checking, 1000 for release hardening.

5. **Set a seed** — always set `set_seed(42)` (or your favorite seed) so failures are reproducible.

6. **Wrap in assert** — `assert(prop_for_all(gen, property, n = 30))` so failures surface as assertion errors.

### Template

```t
set_seed(42)
m = prop_named("sqrt_nonneg", \(x) x < 0.0 || sqrt(x) >= 0.0)
assert(prop_test(m, prop_gen_float_range(-100.0, 100.0), n = 30))
```

### Adding to the test suite

Property tests for T's own packages live in the `tests/` directory alongside existing OCaml tests. Create a `test_property_<pkg>.ml` file, register it in `tests/test_runner.ml` via `run_with_env`, and add it to `tests/dune`. See `tests/math/test_property_math.ml` for an example.

```ocaml
(* tests/math/test_property_math.ml *)
let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
  Printf.printf "Propcraft dogfooding — math:\n";
  let env = Packages.init_env () in
  let (_, env) = eval_string_env {|
    m_sqrt_abs = prop_named("sqrt_abs", \(x) sqrt(x * x) == abs(x))
  |} env in
  test_env env "sqrt(x*x) == abs(x)"
    (Printf.sprintf "set_seed(1)\nprop_test(m_sqrt_abs, %s, n = 30)"
       "prop_gen_float_range(0.0, 100.0)")
    "PASS";
  Printf.printf "\n"
```

---

## Anti-patterns

- **Fixed inputs instead of generators.** `prop_for_all(prop_gen_one_of([1, 2, 3]), ...)` only tests three values. Use `prop_gen_int_range` / `prop_gen_float_range` / `prop_gen_string_from` instead.

- **Too-specific predicates.** `\(x) mean(x) == 25.3` is a regression test, not a property. Ask: "would this still hold if the generator changed?"

- **No seed.** Without `set_seed`, failures are unrepeatable. Always set a seed first.

- **NaN comparisons.** Never use `==` on floats in invariants. Use `abs(a - b) < tolerance` for approximate equality.

- **Ignoring edge cases.** If your function doesn't handle empty strings, negative numbers, or NA, write guards: `s == "" || f(s) == expected`. A property with guard clauses is better than a property that crashes.
