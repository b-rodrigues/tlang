# stats

Statistical summaries and models.

## Functions

| Function | Description |
|----------|-------------|
| `mean(x)` | Arithmetic mean of a numeric list/vector |
| `sd(x)` | Standard deviation |
| `quantile(x, p)` | Compute quantile at probability p |
| `cor(x, y)` | Pearson correlation coefficient |
| `lm(formula, data)` | Linear regression model |
| `min(x)` | Minimum value |
| `max(x)` | Maximum value |

## Examples

```t
mean([1, 2, 3, 4, 5])          -- 3.0
sd([1, 2, 3, 4, 5])            -- 1.5811...
quantile([1, 2, 3, 4, 5], 0.5) -- 3
min([3, 1, 2])                  -- 1
max([3, 1, 2])                  -- 3
```

## Status

Built-in package — included with T by default.
