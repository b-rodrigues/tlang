# complete

Complete a data frame

Turns implicit missing values into explicit missing values. Supports nesting() to restrict combinations to those present in the data.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **...** (`Symbol`): | Call Variable number of column names (use $col syntax) or nesting(...) calls.

- **fill** (`Dict`): (Optional) A dictionary supplying a single value to use instead of NA for missing combinations.

- **explicit** (`Bool`): (Optional) Should both implicit and explicit missing values be filled? (Default: true)


## Returns

The completed DataFrame.

## Examples

```t
complete(df, $group, $item_id, $item_name)
complete(df, $group, nesting($item_id, $item_name))
```

