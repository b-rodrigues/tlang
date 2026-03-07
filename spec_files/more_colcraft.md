# Implementation Guide: Extended Capabilities for T

This document outlines the planned extensions for the `colcraft`, `strings`, `factors`, and `chrono` packages to bring T into full parity with modern data science ecosystems (Tidyverse/Polars).

## 1. Colcraft: Relational Data & Enhanced Selection

### Multi-table Operations (Priority: Critical)
- **`left_join`, `inner_join`, `full_join`**: Relational joins between two DataFrames.
    - *Implementation Note*: Should leverage Arrow's join capabilities via stubs if possible, or implement a hash-join in OCaml/C for `VDataFrame`.
- **`semi_join`, `anti_join`**: Filtering joins to keep/nest rows based on matches in another table.
- **`bind_rows`, `bind_cols`**: Efficient concatenation of DataFrames. `bind_rows` must handle mismatched columns by filling with `NA`.

### Enhanced Selection (Priority: High)
- **`where()`**: Support predicate-based selection (e.g., `select(where(is_numeric))`).
- **`matches()`**: Regex-based column selection.
- **`all_of()` / `any_of()`**: Selection using a vector of names with strict or loose error handling.

---

## 2. Strings: Advanced Regex & Formatting

### Pattern Extraction (Priority: High)
- **`str_extract(s, pattern)`**: Returns the first matching group or substring.
- **`str_extract_all(s, pattern)`**: Returns a List/Vector of all matches.
- **`str_detect(s, pattern)`**: A vectorized regex-based version of `contains()`.

### Formatting & Cleaning (Priority: Medium)
- **`str_pad(s, width, side, pad)`**: Vectorized padding for alignment.
- **`str_trunc(s, width, side, ellipsis)`**: Truncate strings with ellipses.
- **`str_flatten(v, collapse)`**: Collapse a vector into a single string (different from `join` as it targets vector-to-scalar reduction).
- **`str_count(s, pattern)`**: Count occurrences of a regex pattern.

---

## 3. Factors: Categorical Lifecycle Management

### Level Refinement (Priority: Medium)
- **`fct_lump_min(f, min)`**: Lump levels appearing fewer than `min` times.
- **`fct_lump_prop(f, prop)`**: Lump levels appearing in less than `prop` proportion of the data.
- **`fct_other(f, keep, drop)`**: Manually move specific levels to "Other".

### Metadata Management (Priority: Medium)
- **`fct_drop(f)`**: Remove levels that are no longer present in the data (common after `filter()`).
- **`fct_expand(f, ...)`**: Add new potential levels to a factor's metadata.
- **`fct_c(...)`**: Concatenate multiple factor vectors, unifying their level sets.

---

## 4. Chrono: Time-Series & Granularity

### Resampling & Rounding (Priority: High)
- **`floor_date(x, unit)`**: Round down to the nearest `unit` (second, minute, hour, day, month, year).
- **`ceiling_date(x, unit)`**: Round up to the nearest `unit`.
- **`round_date(x, unit)`**: Round to the nearest `unit`.
    - *Implementation Note*: Critical for time-series aggregation (e.g., `df |> group_by(month = floor_date(date, "month"))`).

### Time Zone & Intervals (Priority: Medium)
- **`with_tz(x, tzone)`**: Change the time zone while keeping the instantaneous time the same (clock time changes).
- **`force_tz(x, tzone)`**: Change the time zone label without changing the clock time (instantaneous time changes).
- **Interval Logic**: Implement `%within%` for checking if a date falls in a `VInterval`.

### Utilities (Priority: Low)
- **`is_leap_year(y)`**: Expose existing internal helper as a public function.
- **`days_in_month(y, m)`**: Expose existing internal helper.

---

## Summary of Feature Priority

| Priority | Feature | Category |
| :--- | :--- | :--- |
| **Critical** | Joins (`left_join`, etc.) | Colcraft |
| **High** | Date Rounding (`floor_date`) | Chrono |
| **High** | Regex Extraction (`str_extract`) | Strings |
| **High** | Predicate Selection (`where()`) | Colcraft |
| **Medium** | Concatenation (`bind_rows`, `fct_c`) | Mixed |
| **Medium** | Padding/Truncation | Strings |
| **Medium** | Level Cleaning (`fct_drop`) | Factors |
