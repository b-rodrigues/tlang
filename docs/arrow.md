# Arrow Ingestion Strategy

T prioritizes high-performance data ingestion by leveraging native Apache Arrow and Parquet readers. This document outlines how T handles different formats and its "Native-First" philosophy.

## Native-First CSV Ingestion

T uses a fast, native path for reading CSV files when they follow standard conventions. This path utilize the `GArrowCSVReader` from the Arrow C GLib library, which is significantly faster and more memory-efficient than pure OCaml parsers for large datasets.

### Native Path Activation

The native Arrow CSV reader is used automatically when calling `read_csv()` with its default parameters:
- Comma separator (`,`)
- No skipping of header or lines
- No automatic column name cleaning

If any non-default options are provided (e.g., `separator = ";"`, `skip_lines = 5`), T falls back to a pure OCaml CSV parser. This ensure full compatibility with complex CSV formats while providing maximum speed for standard ones.

### NULL Value Handling (NA)

The native reader is configured to recognize the following strings as `NA` (NA values):
- `NA`
- `na`
- `N/A`
- Empty fields

This ensures consistency between the native reader and the OCaml fallback parser.

## Parquet Support

T provides first-class support for Parquet files via `read_parquet()`. Parquet is the recommended format for large-scale data in T because:
- It is a binary, columnar format with built-in compression.
- Type information is preserved, avoiding the overhead of type inference.
- Native ingestion via `parquet-glib` is faster than CSV reading.
- It supports zero-copy loading of large datasets into memory.

## Technical Fallbacks

If the native Arrow reader fails for any reason (e.g., malformed file, unsupported encoding), T provides a robust fallback mechanism:

1. **Native Attempt**: Try reading using `GArrowCSVReader`.
2. **Warning**: If native reading fails, a warning is printed to stderr.
3. **OCaml Fallback**: The file is re-read using a pure OCaml parser. Note that this fallback is more memory-intensive and may encounter `Out_of_memory` errors for files larger than a few gigabytes on systems with limited RAM.

## Recommendations for Large Data

For datasets exceeding 2-3 GB:
1. **Prefer Parquet**: Convert your CSVs to Parquet using R (`arrow::write_parquet`) or Python (`pandas.to_parquet`) before reading them into T.
2. **Use Standard CSVs**: If you must use CSV, ensure it uses the default comma separator and has no leading comment lines to stay on the high-performance native path.
3. **Memory Limits**: The pure OCaml fallback path is limited by OCaml's heap and string size limits (on 64-bit systems this is large, but still less efficient than Arrow's memory mapping).
