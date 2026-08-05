# prop_test

Run a named property

Runs the property captured by a `prop_named` Dict against values drawn from `gen`, mirroring prop_for_all's parameters. A failing report is prefixed with the property's name.

## Parameters

- **named** (`Dict`): A named property built by prop_named.

- **gen** (`Dict`): A generator spec (see prop_gen_int, prop_gen_df, ...).

- **n** (`Int`): = 100 Number of values to draw.

- **max_counterexamples** (`Int`): = 1 Number of render-distinct failing inputs to report.

- **shrink** (`Bool`): = true Whether to report a shrunk counterexample.

- **shrink_verify** (`Bool`): = false Re-check every shrink candidate so the reported


## Returns

Expect_pass on success, Expect_stop on failure.

## Examples

```t
set_seed(42)
monotone = prop_named("monotone", \(x) x <= 100)
assert(prop_test(monotone, prop_gen_between(0, 200)))
```

## See Also

[prop_for_all](prop_for_all.html), [prop_named](prop_named.html)

