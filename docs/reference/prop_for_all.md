# prop_for_all

Check a property over generated values

Draws `n` values from the `gen` generator spec (using the shared seeded RNG — call set_seed first for reproducible runs) and evaluates `property` on each. The property may return a Bool, an Expect value from testcraft (e.g. expect_equal), or an Error. A property passes only when it returns `true` or `Expect_pass`; `false`, `Expect_stop`, `Expect_hold`, NA, and Error are all treated as failures. On the first failure, a deterministic shrunk counterexample is reported via an Expect_stop value, so `assert(prop_for_all(...))` works inside test files run by `t test`.

## Parameters

- **gen** (`Dict`): A generator spec (see prop_gen_int, prop_gen_df, ...).

- **property** (`Function`): A function from a generated value to Bool or Expect.

- **n** (`Int`): = 100 Number of values to draw.

- **max_counterexamples** (`Int`): = 1 Number of render-distinct failing inputs to report.

- **shrink** (`Bool`): = true Whether to report a shrunk counterexample.

- **shrink_verify** (`Bool`): = false Re-check every shrink candidate (not just the


## Returns

Expect_pass on success, Expect_stop on failure.

## Examples

```t
set_seed(42)
assert(prop_for_all(prop_gen_int_range(0, 100), \(x) x >= 0))
assert(prop_for_all(
prop_gen_df([x: prop_gen_float_range(0.0, 100.0)], nrows = 40, na_prob = 0.1),
\(df) nrow(mutate(df, $z = $x * 2)) == nrow(df)))
```

## See Also

[set_seed](set_seed.html), [expect_equal](expect_equal.html)

