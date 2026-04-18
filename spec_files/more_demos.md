# Specification: Proposed T-Lang Demonstration Projects

This document outlines a roadmap for new demonstration projects in the `t_demos/` repository. These demos are intended to exercise features documented in `tlang/summary.md` that are currently under-tested or lack clear "real-world" representative examples.

## 1. Error Recovery and Resilience (`error_recovery_t`)

**Rationale:** T treats errors as values. While the standard pipe `|>` short-circuits, the `?|>` operator and `is_error` introspection are critical for building resilient production pipelines.

**Key Functions:**
- `?|>` (Forwarding Pipe)
- `is_error(x)`
- `error_message(x)`
- `error_code(x)`
- `ifelse()` for recovery logic

**Demo Scenario:**
- A pipeline that attempts to read a CSV that might be missing or corrupt.
- Use `?|>` to catch the error.
- A recovery node checks `if (is_error(data))`, logs the error message to a text file, and provides a default empty DataFrame so the rest of the pipeline (e.g., a Quarto report) can still build without a hard crash.

---

## 2. Advanced Data Reshaping (`tidy_reshaping_t`)

**Rationale:** The `colcraft` package implements most of the `tidyr` verb set. We need to verify that T can handle complex schema pivots and nested data structures natively.

**Key Functions:**
- `pivot_longer()`, `pivot_wider()`
- `separate()`, `unite()`
- `nest()`, `unnest()`
- `crossing()`, `expand()`

**Demo Scenario:**
- "Cleaning Messy WHO Data": Take a dataset with columns like `m014`, `m1524` (sex + age combined in headers).
- Use `pivot_longer` and `separate` to create clean `sex` and `age` columns.
- Use `nest` to create a "grouped" dataframe for per-group modeling, then `unnest` to compare results.

---

## 3. Temporal Analysis and Period Math (`chrono_analysis_t`)

**Rationale:** Datetime logic is notoriously bug-prone. We need a demo that exercises parsing, truncation, and arithmetic across different granularities.

**Key Functions:**
- `ymd()`, `dmy_hms()`
- `floor_date()`, `ceiling_date()`
- `years()`, `months()`, `days()` (Periods)
- `with_tz()`, `force_tz()` (Labeling checks)

**Demo Scenario:**
- "Contract Value Calculator": Given a list of start dates and contract durations.
- Calculate expiry dates using period addition.
- Group by "Expiry Quarter" using `floor_date(date, "quarter")`.
- Verify the "Label-only" behavior of timezones as documented in `summary.md`.

---

## 4. Advanced Metaprogramming Lifecycle (`advanced_nse_t`)

**Rationale:** `get_sym_demo_t` covers simple lookup. We need to demonstrate "Lazy Evaluation" for users writing their own domain-specific wrappers.

**Key Functions:**
- `quo()`, `enquo()`
- `eval()`
- `expr()`
- `as_string()` / `sym()` converters

**Demo Scenario:**
- Create a custom function `my_summarizer = \(df, col) { ... }` that uses `enquo(col)` to capture a column reference and `eval()` it inside a `summarize` block.
- Demonstrate how to programmatically build a pipeline step using `expr()`.

---

## 5. Auditable Pipelines with Intent Metadata (`auditable_pipeline_t`)

**Rationale:** T is designed for human-LLM collaboration. `intent {}` blocks provide the "Why" that standard code comments lack.

**Key Functions:**
- `intent { ... }` blocks
- `explain(node)`
- `explain_json(node)`

**Demo Scenario:**
- A "Credit Scoring" pipeline where every node (Data Cleaning, Feature Engineering, Model Training) has an `intent` block documenting the regulatory assumptions used.
- A final "Audit Node" calls `explain()` on all previous nodes and generates a summary text file for human review.

---

## 6. Matrix Algebra and Custom Models (`matrix_math_t`)

**Rationale:** Ensure the `ndarray` and linear algebra builtins in the `math` package are robust for users who want to avoid R/Python for simple numerical tasks.

**Key Functions:**
- `ndarray()`, `reshape()`
- `matmul()` (or `@` if supported)
- `transpose()`, `inv()`
- `standardize()`, `normalize()`

**Demo Scenario:**
- implement a "Bare Metal" OLS (Ordinary Least Squares) solver using the normal equation: $\hat{\beta} = (X^T X)^{-1} X^T y$.
- Compare the coefficients with the native `lm()` function to verify numerical stability.

---

## 7. Factor Engineering (`factor_clean_t`)

**Rationale:** Categorical data is a first-class citizen in `colcraft`. We need to show how to handle "Other" categories and reordering.

**Key Functions:**
- `fct_lump_n()`, `fct_lump_prop()`
- `fct_reorder()`, `fct_relevel()`
- `fct_recode()`

**Demo Scenario:**
- "Social Survey Cleaning": A dataset with 50+ unique country names.
- Lump all but the top 5 into "Other".
- Reorder a "Satisfaction" factor (Low, Medium, High) which is alphabetically incorrect.
- Recode old category names to new ones.

---

## 8. High-Fidelity Equality and Introspection (`integrity_check_t`)

**Rationale:** In a reproducibility-first language, verifying that two runs produced *exactly* the same complex objects is vital.

**Key Functions:**
- `identical()`
- `glimpse()`
- `digest()` (if available) or `explain_json()` comparison

**Demo Scenario:**
- Generate two models using slightly different data and show that `==` might be misleading (or limited) while `identical()` correctly identifies structural differences in the model metadata.
