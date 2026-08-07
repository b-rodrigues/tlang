# prop_stats

Probe a generator's behaviour

Draws `n` values from `gen`, ramping the generation size from 1 to `n`, and returns a Dict summarizing what was produced: run counts, the value types observed, the sizes of any Vector/List/DataFrame values, and the wall-clock time spent.

## Parameters

- **gen** (`Dict`): A generator spec (see prop_gen_int, prop_gen_df, ...).

- **n** (`Int`): = 100 Number of draws (also the max size ramp).


## Returns

{ n_runs, n_errors, value_types, nested_sizes, elapsed_ms }.

## Examples

```t
prop_stats(prop_gen_df([x: prop_gen_int_range(0, 10)]), n = 20)
```

## See Also

[prop_for_all](prop_for_all.html)

