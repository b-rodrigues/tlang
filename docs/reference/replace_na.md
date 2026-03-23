# replace_na

Replace missing values

replace_na() replaces missing values with specified values.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **replace** (`Dict`): A list of named values to use for replacing NA.


## Returns

The DataFrame with NA replaced.

## Examples

```t
replace_na(df, [age: 0, score = 0])
```

