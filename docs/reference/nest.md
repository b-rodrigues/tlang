# nest

Nest columns into sub-dataframes

Packs selected columns into nested DataFrame values grouped by the remaining columns. Supports flexible column selection using symbols, strings, or selection helpers (like starts_with, ends_with).  If the DataFrame is already grouped (via group_by()) and no columns are specified, nest() will automatically nest all columns except the grouping keys.

## Parameters

- **data** (`Selection`): (Optional) Columns or matchers to nest.

- **df** (`DataFrame`): The DataFrame to nest.

- **name** (`String`): (Optional) Name for the new nested column, defaults to "data".

- **...** (`Selection`): (Optional) Positional columns to nest if 'data' is not provided.


## Returns

A new DataFrame with grouped keys and a nested list-column.

