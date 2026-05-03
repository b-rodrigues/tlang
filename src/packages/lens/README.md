# lens

Composable functional lenses for nested data structures.

## Functions

| Function | Description |
|----------|-------------|
| `col_lens(name)` | Focus on a dict key or dataframe column |
| `idx_lens(i)` | Focus on a list/vector index |
| `row_lens(i)` | Focus on a dataframe row |
| `filter_lens(p)` | Focus on elements matching a predicate |
| `node_lens(name)` | Focus on a pipeline node's result |
| `compose(...)` | Combine multiple lenses |
| `get(data, lens)` | Retrieve value at focus |
| `set(data, lens, v)` | Set value at focus |
| `over(data, lens, fn)` | Transform value at focus |
| `modify(data, ...)` | Apply multiple transformations |

## Examples

```t
df = dataframe([a: [1, 2], b: [3, 4]])

-- Extract column
get(df, col_lens("a"))       -- [1, 2]

-- Update row
new_df = over(df, row_lens(0), \(r) set(r, col_lens("a"), 10))
```

## Status

Built-in package — included with T by default.
