# Factors Implementation Spec

## Current Status (Alpha)
T does not yet have a native `Factor` or `Categorical` type. Currently, categorical data is treated as a `StringColumn` in Arrow and `VString` at the language level. This leads to alphabetical sorting instead of level-based sorting.

## Architectural Goal
To support factors while maintaining parity with Arrow's FFI and R's semantics:

1.  **Arrow Layer**:
    *   Extend `arrow_type` and `column_data` in `src/arrow/arrow_table.ml` to include a `DictionaryColumn`.
    *   This column type will wrap Arrow's `DictionaryArray`, which stores common values (levels) once and uses an integer array for indices (rows).

2.  **Language Level**:
    *   Add `VFactor` to the `value` type in `src/ast.ml`. 
    *   `VFactor` should carry:
        *   An integer index.
        *   A reference to an immutable list of levels.
        *   An `ordered` boolean flag.

3.  **Functions for the Future**:
    *   `factor(x, levels, ordered)`: Manual creation.
    *   `as_factor(x)`: Automatic creation based on unique values.
    *   `fct_reorder(f, x, fun)`: Reordering levels based on another variable.
    *   `fct_infreq(f)`: Reordering levels by frequency.

## Sorting Semantics
Once implemented, `arrange()` must check for factor types. Comparison between factors should be based on their dictionary indices (level order) rather than their string representations.
