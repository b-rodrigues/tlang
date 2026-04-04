# Contextual Data Access in Mutate

## Current Limitation: The `$everything` Fallacy

Inside `mutate()` or `filter()` blocks, symbols are resolved against the columns of the DataFrame being processed. 
However, there is currently no native way to refer to the **entire DataFrame object** within an expression in a vectorized way.

### The Issue

If you try to call a function that expects a whole DataFrame (like `predict()`) inside a `mutate()`:

```t
df |> mutate($y = predict($everything, model))
```

The symbol `$everything` (or any other attempted name) will fail because:
1.  Symbols are treated as column lookups (returning Vectors).
2.  `predict()` expects a `VDataFrame`.
3.  Even if it worked, passing a fixed DataFrame to a vectorized function might lead to unexpected behavior if not handled by the emitter/evaluator.

### Current Workaround

Perform the multi-column operation outside the `mutate` block and then bind the results:

```t
X = df |> select($feature1, $feature2)
preds = predict(X, model)  # Returns a Vector
df |> mutate($y = preds)   # Vector assignment works as expected
```

## Proposal: `cur_data()`

To match the ergonomics of `dplyr::cur_data()` or `pandas`'s `lambda x: ...` style access, we should explore a builtin that returns the current subset of the DataFrame being operated on:

- **Syntax**: `mutate($y = predict(cur_data(), model))`
- **Implementation**: The `mutate` evaluator would need to inject a special `cur_data` value or function into the environment of the expression being evaluated for each group/chunk.
- **Scope**: Also useful for custom aggregation functions and row-wise operations.

---
*Note: This enhancement is planned for the v0.52.x series refocusing on DataFrame ergonomics.*
