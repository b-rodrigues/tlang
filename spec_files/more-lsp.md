# Future LSP Enhancements for T

This document tracks planned features for the T Language Server Protocol (LSP) to improve the development experience, particularly for data science workflows.

## 1. Column Name Autocompletion (PRIORITY)
- **Description**: Provide suggestions for column names when using the `$` prefix or within data-masking functions (filter, select, mutate, etc.).
- **Implementation**: Requires the LSP to track the schema (column names) of `DataFrame` symbols in the `Symbol_table`.
- **Trigger**: Typing `$` or being inside a function call that operates on a known DataFrame.

## 2. Signature Help (Arg Hints)
- **Description**: Show a floating tooltip with the function signature and highlight the active parameter.
- **Trigger**: Typing `(` after a function name.

## 3. Document Symbols (Outline)
- **Description**: Populate the editor's symbol tree/outline with function definitions and top-level variables.
- **Benefit**: Easier navigation in large `.t` files.

## 4. Interactive Data Preview
- **Description**: Enhance the hover tooltip for `DataFrame` variables to show a summary (e.g., `nrow`, `ncol`, and first 5 rows).

## 5. Semantic Highlighting & Linting
- **Description**: Use the analyzer's results to provide more accurate syntax highlighting (e.g., distinguishing built-ins from local variables) and live warnings (e.g., unused variables).
