# Specification: NA Handling Policy (Proposed)

Status: Proposed / Brainstorming
Author: Bruno Rodrigues
Date: 2026-04-11

## Architecture Goal
T-Lang aims for a "Data Frame First" and "Reproducible" design. To balance safety and ergonomics, we distinguish between **Transformations** and **Aggregations** when handling missing data (`NA`).

## 1. Transformations (Element-wise / Vectorized)
Functions that apply a mapping independently to every element of a collection (or a scalar) should **propagate** NAs.

- **Examples**: `abs()`, `log()`, `exp()`, `sqrt()`, `+`, `-`, `*`, `/`, `cat()`, `substr()`.
- **Behavior**: If the input is `NA`, the result is `NA`.
- **Warning System**: Propagation should ideally trigger a non-halt diagnostic warning (e.g. `Warning: abs() encountered NA values; 5 rows propagated as NA`).
- **Rationale**: This allows for long chains of data cleaning without "poison pill" errors interrupting the flow. Missingness is captured and carried through to the finish line.

## 2. Aggregations (Summaries)
Functions that reduce a collection to a smaller set of values (summaries) should **error** by default if NAs are present.

- **Examples**: `sum()`, `mean()`, `sd()`, `cor()`, `max()`, `min()`.
- **Behavior**: If `NA` is detected and `na_rm = false` (the default), the function must return an `Error (TypeError)`.
- **Opt-out**: The user must explicitly set `na_rm = true` to ignore missing values in the summary.
- **Rationale**: An average or total of "Something Unknown" is logically "Unknown" but mathematically dangerous. Forcing the user to add `na_rm = true` ensures they are conscious of the data quality at the point of decision/reporting.

## 3. Explicit vs. Implicit
This policy moves from "Strict Everywhere" to "Propagate on Transform, Error on Aggregate".

| Operation | Input | Current Behavior | Proposed Behavior |
| :--- | :--- | :--- | :--- |
| `abs(NA)` | `NA` | `Error` | `NA` (with Warning) |
| `mean([1, NA, 3])` | `[1, NA, 3]` | `Error` | `Error` (Unchanged) |
| `mean([1, NA, 3], na_rm=true)` | `[1, NA, 3]` | `2` | `2` (Unchanged) |

## 4. Implementation Notes
- Pure math builtins in `math/` should be updated to return `VNA` instead of `Error`.
- Vectorized iterators in OCaml should continue the loop but populate the result array with `VNA`.
- The `mean` and `sum` implementations already have `na_rm` logic, but they should keep their strict error-on-missing-without-rm behavior.
