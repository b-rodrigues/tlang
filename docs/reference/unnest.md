# unnest

Expand nested columns

Expands a nested list-column (produced by nest() or similar) back into its constituent rows and columns, effectively duplicating rows of the "parent" DataFrame for every row in the nested table.

## Parameters

- **df** (`DataFrame`): The DataFrame containing a nested column.

- **cols** (`Column`): Selection column to unnest (positional or 'cols=' arg).


## Returns

The expanded DataFrame.

