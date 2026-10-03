# distinct

Keep unique rows

Returns the distinct rows of a DataFrame, optionally using selected columns as uniqueness keys.

## Parameters

- **df** (`DataFrame`): The input DataFrame.

- **...** (`Symbol`): Optional uniqueness key columns.

- **.keep_all** (`Bool`): [Optional] Keep all columns. Defaults to false.


## Returns

The DataFrame with unique rows.

