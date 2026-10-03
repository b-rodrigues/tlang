# relocate

Move columns to a new position

Reorders DataFrame columns by moving selected columns before or after another column.

## Parameters

- **df** (`DataFrame`): The input DataFrame.

- **...** (`Symbol`): Columns to move.

- **.before** (`Symbol`): [Optional] Move before this column.

- **.after** (`Symbol`): [Optional] Move after this column.


## Returns

The DataFrame with reordered columns.

