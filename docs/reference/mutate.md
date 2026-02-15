# mutate

Create or modify columns

Adds new columns or modifies existing ones.

## Parameters

- **df** (`DataFrame`): The input DataFrame.
- **...** (`KeywordArgs`): New columns as name = expression pairs.

## Returns

The modified DataFrame.

## Examples

```t
mutate(mtcars, $hp_per_wt = $hp / $wt)
```

## See Also

[select](select.md), [summarize](summarize.md)

