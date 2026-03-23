# More Tidyr Functions Implementation Spec

## Future Function Roadmap
The following functions are targeted for future expansion to complete the "Tidyverse-in-T" experience.

### Column Organization
*   **`rename(df, ...)`**: A lightweight alternative to `mutate()` for renaming.
*   **`relocate(df, ..., .before, .after)`**: Reordering columns by name or pattern.
*   **Selection Helpers**: `starts_with()`, `ends_with()`, `contains()`, `everything()`.

### Uniqueness and Slicing
*   **`distinct(df, ..., .keep_all)`**: Fast deduplication of rows.
*   **`slice(df, indices)`**: Positional row selection.
*   **`slice_max(df, order_by, n)` / `slice_min()`**: Top/bottom-N row selection.
*   **`count(df, ..., name = "n")`**: Group; summarize(n = nrow()); ungroup() in one step.

### Complex Reshaping and List-Columns
*   **`nest(df, ..., .key = "data")`**: Grouping rows and storing the sub-tables as list-columns.
*   **`unnest(df, cols)`**: Flattening list-columns back into individual rows.
*   **`separate_rows(df, ..., sep = "[^[:alnum:].]")`**: Splitting a string into multiple rows.
*   **`uncount(df, weights, .remove = true)`**: Expanding rows based on a frequency column.

## Architectural Decision: List-Column Support
To maintain performance and FFI compatibility, T's `VDataFrame` must **never** move away from its Arrow backing. 

1.  **Native Arrow Serialization**:
    *   List-columns will be implemented using Arrow's **`List` and `Struct`** types.
    *   `src/arrow/arrow_table.ml` will be extended to include a `ListColumn` in the `column_data` enum.
    *   This ensures that even complex nested DataFrames can be passed directly to Python or R via Arrow IPC/Feather with zero conversion overhead.

2.  **Implementation Warning**:
    *   Do **not** implement a custom "T-nested-dataframe" type in the AST. 
    *   The `VDataFrame` value should always represent a single `Arrow_table.t`. Nesting is achieved by that table containing columns of type `List(Table)`.

3.  **Recursive Verb Logic**:
    *   Verbs like `mutate()` or `summarize()` must be updated to handle `ListColumn` types. 
    *   Aggregating a `ListColumn` into a scalar might return a new Table or a List of values.
