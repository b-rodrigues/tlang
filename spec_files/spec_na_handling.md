# Specification: NA Handling Policy

Status: Draft
Author: Bruno Rodrigues
Date: 2026-04-11

## Architecture Goal

T-Lang aims for a "Data Frame First" and "Reproducible" design. The NA handling policy is built around one core principle: **missingness must always be a conscious, explicit decision**. There is no silent propagation. Every function that encounters an `NA` either errors (forcing the user to decide) or accepts an explicit opt-in parameter that documents the decision in the pipeline graph itself.

Two parameters govern this, named to reflect their distinct semantics:

- `na_ignore = true` — for **vectorized/transformation** functions: skip the slot, leave `NA` in place, preserve output length
- `na_rm = true` — for **aggregation and window** functions: remove NAs from the set before computing

These are intentionally not interchangeable. The parameter name signals the operation type.

---

## 1. Transformations (Element-wise / Vectorized)

Functions that apply a mapping independently to every element of a collection.

**Examples**: `abs()`, `log()`, `exp()`, `sqrt()`, `+`, `-`, `*`, `/`, `cat()`, `substr()`.

**Default behavior**: If any input element is `NA`, the function **errors**.

```
log([1, 2, NA])
-- Error: log() encountered NA at index 3. Use na_ignore=true to skip NA slots,
--        or handle NAs explicitly before this step.
```

**Opt-in with `na_ignore = true`**: The function skips `NA` slots and returns `NA` in those positions. Output length is always preserved — a 3-element input always produces a 3-element output. This is not a different computation; it is an explicit declaration that the caller is aware of the NAs and accepts that those slots will remain missing.

```
log([1, 2, NA], na_ignore=true)
-- Result: [0.0, 0.693, NA]
```

**Rationale**: A transformation that silently propagates NAs hides data quality issues inside long pipeline chains. Erroring by default forces the decision to be made at the point where missingness is first encountered, not discovered at the end of a report.

**`na_ignore` is not a warning suppressor** — it is a semantic declaration. Even with `na_ignore=true`, the node records how many slots were skipped in its diagnostic metadata (see Part 2: Node Diagnostics).

---

## 2. Aggregations (Summaries)

Functions that reduce a collection to a smaller set of values.

**Examples**: `sum()`, `mean()`, `sd()`, `cor()`, `max()`, `min()`.

**Default behavior**: If `NA` is present and `na_rm = false` (the default), the function **errors**.

```
mean([1, NA, 3])
-- Error (AggregationError): mean() encountered NA values. The mean of an incomplete
--   set is undefined. Use na_rm=true to exclude NAs, or handle them explicitly beforehand.
```

**Opt-in with `na_rm = true`**: NAs are excluded from the computation. The function operates on the remaining values only.

```
mean([1, NA, 3], na_rm=true)
-- Result: 2.0
-- (computed over [1, 3])
```

**Error type**: `AggregationError`, not `TypeError`. `NA` is a valid value of any type; the issue is semantic — you are asking for a summary of an incomplete set.

**Rationale**: An average or total over a set containing unknowns is itself unknown. Forcing the explicit `na_rm=true` ensures the user is conscious of data quality at the point of reporting or decision-making.

---

## 3. Window / Rolling Functions

Window functions (e.g. `rolling_mean()`, `rolling_sum()`) perform a local reduction over a sliding window. They are treated as **aggregations**, not transformations.

**Default behavior**: If any value within a window contains `NA`, the function **errors**.

**Opt-in with `na_rm = true`**: NAs are excluded from each window's computation independently.

```
rolling_mean(col, window=3, na_rm=true)
-- Each window of 3 computes its mean over non-NA values only.
-- A window composed entirely of NAs returns NA for that position.
```

**Rationale**: A rolling mean over a window containing `NA` is as semantically ambiguous as a global mean. The "local" nature of the reduction does not change the underlying problem. The `na_rm=true` semantics apply *per window*, which is subtly different from the global aggregation case and should be noted in documentation.

---

## 4. Filter and Boolean Predicates

`filter()` expressions involve a predicate that is evaluated over a column. When the predicate column contains NAs, T follows **R semantics**: NA rows are excluded from the filtered result (they are neither matched nor explicitly kept).

However, unlike R, this exclusion is **not silent**. T raises a diagnostic warning at the node level:

```
filter(df, blabl == 2)
-- Warning: filter(blabl == 2): column 'blabl' has 7 NAs.
--   These rows were excluded from the result.
--   Consider handling NAs explicitly before filtering.
```

The warning reports the column name and the count of NA rows excluded, so the user can immediately assess whether this is a trivial edge case or a material data quality issue without running a separate diagnostic step.

Filter does not error by default because dropping NA rows from a predicate result is the universally expected behaviour and making it an error would be impractical. The warning closes the gap by surfacing the implicit exclusion explicitly.

---

## 5. Idiomatic NA Handling in Pipelines

The preferred T idiom is to handle NAs as **explicit pipeline nodes** rather than through function parameters wherever possible. This makes the decision visible in the pipeline graph and ensures it is captured in node diagnostics.

```t
-- Preferred: explicit node, visible in graph, auditable
clean_col = drop_na(raw_col)
result    = log(clean_col)

-- Also acceptable: declared intent via parameter
result = log(raw_col, na_ignore=true)

-- Avoid: relying on downstream aggregation to surface the issue silently
result = mean(raw_col)   -- errors, correctly
```

`drop_na()` is first-class pipeline nodes with their own diagnostics. Using them explicitly is preferred because it documents the choice in the pipeline structure, not just in a function argument.

---

## 6. Behaviour Summary

| Operation | Input | Default Behaviour | With Opt-in |
| :--- | :--- | :--- | :--- |
| `log(NA)` | `NA` | `Error` | `NA` (`na_ignore=true`) |
| `log([1, NA, 3])` | `[1, NA, 3]` | `Error` | `[0.0, NA, 1.099]` (`na_ignore=true`) |
| `abs(NA)` | `NA` | `Error` | `NA` (`na_ignore=true`) |
| `mean([1, NA, 3])` | `[1, NA, 3]` | `AggregationError` | `2.0` (`na_rm=true`) |
| `sum([1, NA, 3])` | `[1, NA, 3]` | `AggregationError` | `4.0` (`na_rm=true`) |
| `rolling_mean(col, window=3)` with NA in window | window contains `NA` | `AggregationError` | computed over non-NA values (`na_rm=true`) |
| `filter(df, col == 2)` with NA in `col` | NA rows | Warning, rows excluded | — |
| `NA == 5` (standalone) | `NA` | `Error` | `NA` (`na_ignore=true`) |

---

## 7. Implementation Notes

- Pure math builtins in `math/` should check for `VNA` inputs and return `Error` by default; return `VNA` when `na_ignore=true` is set.
- Vectorized iterators in OCaml: when `na_ignore=true`, continue the loop and populate the result array with `VNA` at skipped positions. When `na_ignore=false` (default), abort on first `VNA` encountered.
- `mean`, `sum`, and window functions: existing `na_rm` logic is correct; ensure the default (`na_rm=false`) path raises `AggregationError`, not a generic error.
- `filter()`: implement R-style NA exclusion with a structured warning emitted to the node's diagnostic record (see Part 2).
- All `na_ignore` and `na_rm` invocations must record the NA count and affected indices in the node's diagnostic metadata regardless of whether an error or warning is raised.
