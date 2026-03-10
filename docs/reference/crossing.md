# crossing

Create a data frame from all combinations of inputs

crossing() generates all unique combinations of its inputs. Unlike expand_grid(), it de-duplicates and sorts its inputs.

## Parameters

- **...** (`Vector`): | List Named or unnamed inputs to combine.


## Returns

A DataFrame with all unique combinations.

## Examples

```t
crossing(x = 1:3, y = ["a", "b"])
```

