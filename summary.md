# LLM Context: The T Programming Language

The **T Programming Language** is an experimental, reproducibility-first functional language designed for declarative data analysis. It aims to reduce bugs and ensure strict reproducibility by mandating that high-level workflows are executed as statically defined **Pipelines** powered by **Nix**.

## Core Concepts

- **Reproducibility First**: Packages and environments are defined using Nix flakes.
- **Mandatory Pipelines**: Non-interactive execution requires defining a `pipeline`, enforcing DAG-based computation to prevent spaghetti code. 
- **Polyglot Architecture**: T orchestrates code. You can have `node` blocks that run natively in T, or external blocks (`rn()` for R, `pyn()` for Python). 
- **Object Interchange**: T uses Apache Arrow for data frames and PMML for models, passing data natively between R, Python, and T without serialization overhead or loss of fidelity. Factor (categorical) columns are stored natively as Arrow Dictionary arrays for efficient interop.
- **Arrow Native Safety**: Native Arrow select/filter stays on the zero-copy path with telemetry, plus stricter FFI bounds checks.
- **PMML Schema Validation**: PMML imports are validated against the PMML 4.4.1 schema for interoperability.
- **Immutability and No Loops**: T has no loops and no mutable variables.
- **Explicit NA Handling**: NA does not propagate silently; if NA is encountered in aggregation functions without `na_rm = true`, an error is thrown. 
- **Context-Aware Errors**: Errors include source locations (line/column, plus filename when available).
- **Non-Standard Evaluation (NSE)**: Uses `$` prefix for referring to variables/columns concisely (e.g. `filter($age > 30)`).

## Basic Syntax

```t
-- Variable assignment
x = 10
name = "Alice"

-- Function definition (lambda style preferred)
add = \(a, b) a + b

-- Conditionals
result = if (x > 5) "high" else "low"

-- Pipe operators
-- |> passes left-hand to right-hand, short-circuits on Error
-- ?|> forwards left-hand to right-hand even if it is an Error for recovery
[1, 2, 3] |> map(\(v) v * v) |> sum

-- Import a whole package
import mypackage

-- Import specific names from a package
import mypackage [fn1, fn2]

-- Import specific names from another .t file
import "helpers.t" [clean_data, normalize]

-- Sequence generation
seq(5)                         -- [1, 2, 3, 4, 5]
seq(1, 10, by = 2)             -- [1, 3, 5, 7, 9]
```

## Tooling

### REPL
The T REPL (`dune exec src/repl.exe`) supports:
- **Readline editing** with arrow keys, history navigation
- **Persistent history** in `~/.t_history` (up to 1000 entries)
- **Ghost hints**: greyed-out inline completions from history
- **Multi-line input**: automatically detected for open brackets, parens, braces
- **Magic commands**: `:help`, `:quit`, `:clear` (or prefix `run_file("path.t")` to execute a script)
- **Signal-safe interrupts**: Ctrl+C cancels evaluation and returns to the prompt without crashing
- **Stricter CLI flag validation**: `--mode`/`--unsafe` are rejected on conflicting commands

### Language Server Protocol (LSP)
T ships a native LSP server (`t-lsp`) that integrates with VS Code and other editors:
- **Completion**: symbol, variable, function, and DataFrame column completion
- **Go to Definition**: jump to where a binding is defined
- **Hover info**: inline documentation from `--#` docstrings
- **Diagnostics**: parse and type errors shown inline
Configure your editor to launch `t-lsp` as the language server for `.t` files.

## Data Manipulation (Data Verbs)

T includes a standard library (`colcraft`) for data manipulation with dplyr- and tidyr-like verbs. All verbs require NSE (`$col`) syntax for column references.

### Core dplyr-style verbs
- `select($col1, $col2)`: Select columns
- `filter($age > 25)`: Filter rows
- `mutate($bonus = $salary * 0.1)`: Create/modify columns using NSE lambdas
- `arrange($age, "desc")`: Sort rows
- `group_by($dept)`: Group data for aggregation
- `summarize($avg = mean($salary))`: Aggregate data per group

### Column management
- `rename($new_name = $old_name, ...)`: Rename columns
- `relocate($col, .before = $ref_col)` / `relocate($col, .after = $ref_col)`: Reorder columns
- `distinct($col1, $col2, .keep_all = false)`: Keep unique rows
- `count($col1, $col2, name = "n")`: Count observations by group

### Row selection
- `slice(df, indices)`: Select rows by integer index (0-based)
- `slice_min(df, order_by = $col, n = 1)`: Keep rows with smallest values
- `slice_max(df, order_by = $col, n = 1)`: Keep rows with largest values
- `head(df, n = 6)`: First n rows of a DataFrame, List, or Vector
- `tail(df, n = 6)`: Last n rows of a DataFrame, List, or Vector

### Data reshaping (tidyr-style)
- `pivot_longer(df, $col1, $col2, names_to = "name", values_to = "value")`: Widen → long
- `pivot_wider(df, names_from = $col, values_from = $col)`: Long → wide
- `complete(df, $col1, $col2, fill = [:], explicit = true)`: Make implicit missing values explicit
- `expand(df, $col1, $col2)`: Create all combinations of column values
- `crossing(...)`: Cartesian product of vectors/lists (de-duplicated and sorted)
- `nesting(...)`: Helper used inside `expand`/`complete` to restrict to observed combinations

### String & column splitting/joining
- `separate(df, $col, into = ["a", "b"], sep = "[^[:alnum:]]+", remove = true)`: Split one column into many
- `unite(df, "new_col", $col1, $col2, sep = "_", remove = true)`: Combine columns into one
- `separate_rows(df, $col, sep = "[^A-Za-z0-9]+")`: Split values and expand into new rows
- `uncount(df, $weights, .remove = true)`: Duplicate rows according to a weight column

### Multi-table verbs
- `left_join(df1, df2, by = "id")`: Keep all left-hand rows and append matching right-hand columns
- `inner_join(df1, df2, by = "id")`: Keep only matching rows from both inputs
- `full_join(df1, df2, by = "id")`: Keep matching rows plus unmatched rows from both inputs
- `semi_join(df1, df2, by = "id")`: Keep left-hand rows that have at least one match
- `anti_join(df1, df2, by = "id")`: Keep left-hand rows that have no match
- `bind_rows(df1, df2, ...)`: Stack DataFrames by rows, filling missing columns with `NA`
- `bind_cols(df1, df2, ...)`: Combine DataFrames side-by-side by columns

### Missing value handling
- `drop_na(df, ...)`: Drop rows with NA in any (or specified) columns
- `replace_na(df, replace = [col: value, ...])`: Replace NA with specified values per column (pass a Dict using T's `[key: value, ...]` literal syntax)
- `fill(df, $col, .direction = "down")`: Fill NA using adjacent values (`"down"`, `"up"`, `"downup"`, `"updown"`)

### Nested data
- `nest(df, $col1, $col2, name = "data")`: Collapse columns into a list-column of sub-DataFrames
- `unnest(df, $col)`: Expand a list-column of DataFrames back into rows

### Selection helpers (use inside `select`)
- `starts_with("prefix")`: Match columns whose names start with prefix
- `ends_with("suffix")`: Match columns whose names end with suffix
- `contains("pattern")`: Match columns whose names contain a literal string
- `everything()`: Select all remaining columns
- `where(is_numeric)`: Select columns whose values satisfy a builtin predicate helper
- `matches("^prefix")`: Select columns whose names match a regex
- `all_of(["a", "b"])`: Require an explicit set of column names
- `any_of(["a", "missing"])`: Select only the names that are present

### Factor (categorical) support
- `factor(x, levels = [], ordered = false)`: Convert vector to factor with explicit levels (sorted by default)
- `fct(x, levels = [], ordered = false)`: Like `factor` but levels follow first-appearance order
- `ordered(x, levels)`: Shorthand for `factor(..., ordered = true)`
- `as_factor(x)`: Alias for `factor()`
- `levels(x)`: Extract level labels from a factor
- `fct_rev(x)`: Reverse level order
- `fct_recode(x, new = $old, ...)`: Rename individual levels
- `fct_reorder(f, x, .desc = false)`: Reorder levels by median of another variable
- `fct_relevel(f, $level1, ..., after = 0)`: Move specified levels to a given position
- `fct_lump_n(x, n = 10, other_level = "Other")`: Keep top n levels, collapse the rest
- `fct_lump_min(x, min, other_level = "Other")`: Collapse levels that appear fewer than `min` times
- `fct_lump_prop(x, prop, other_level = "Other")`: Collapse levels whose observed proportion is below `prop`
- `fct_infreq(x)`: Reorder levels by decreasing frequency
- `fct_collapse(x, new_level = [$old1, $old2], ...)`: Collapse multiple levels into one
- `fct_other(x, keep = [...], drop = [...], other_level = "Other")`: Keep or drop specific levels by moving the rest to `Other`
- `fct_drop(x)`: Remove unused levels from factor metadata
- `fct_expand(x, ...)`: Add new potential levels without changing existing observations
- `fct_c(x1, x2, ...)`: Concatenate factor vectors while unifying their levels

**Native Arrow backing**: Factors are stored as Arrow `DictionaryArray` (int32 indices + string dictionary) when the native Arrow backend is active. DataFrames containing factor columns can be fully materialized into native Arrow tables, enabling zero-copy operations (select, filter, sort) on factor data. The `ordered` flag is encoded in Arrow's `DictionaryDataType` and preserved through native materialization round-trips. List-columns (nested DataFrames from `nest()`) are stored as Arrow `ListArray<StructArray>` and can be fully materialized into native Arrow tables when all nested fields are primitive types (Int64, Float64, Boolean, String), enabling native Arrow compute operations on nested DataFrames.

### String helpers
- `str_extract(s, pattern)`: Return the first regex match (or first capture group when present)
- `str_extract_all(s, pattern)`: Return every regex match as a list
- `str_detect(s, pattern)`: Vectorized regex predicate
- `str_pad(s, width, side = "left", pad = " ")`: Pad strings to a target width
- `str_trunc(s, width, side = "right", ellipsis = "...")`: Truncate strings with an ellipsis
- `str_flatten(x, collapse = "")`: Collapse a vector or list into a single string
- `str_count(s, pattern)`: Count regex matches

### Chrono helpers
- `floor_date(x, unit)` / `ceiling_date(x, unit)` / `round_date(x, unit)`: Round dates and datetimes to calendar boundaries
- `with_tz(x, tz)` / `force_tz(x, tz)`: Current implementation treats timezones as labels only, so both update the attached timezone label without offset conversion
- `interval(start, end)`: Construct an interval from two date-like values
- `` `%within%`(x, interval) ``: Test whether a date or datetime lies inside an interval
- `is_leap_year(x)` / `days_in_month(x)`: Expose calendar helpers for leap years and month lengths

### Window functions (for use inside `mutate`)
- **Ranking**: `row_number(x)`, `min_rank(x)`, `dense_rank(x)`, `percent_rank(x)`, `cume_dist(x)`, `ntile(x, n)`
- **Cumulative**: `cumsum(x)`, `cummin(x)`, `cummax(x)`, `cummean(x, na_rm = false)`, `cumall(x)`, `cumany(x)`
- **Offset**: `lag(x, n = 1)`, `lead(x, n = 1)`

Example:
```t
df = read_csv("data.csv")
result = df
  |> filter($age >= 18)
  |> group_by($category)
  |> summarize($avg_spend = mean($spend, na_rm = true), $count = nrow($category))

-- Pivot to wide format
wide = result |> pivot_wider(names_from = $category, values_from = $avg_spend)

-- Window functions inside mutate
ranked = df |> mutate($rank = dense_rank($salary), $delta = $salary - lag($salary))

-- Factor encoding
df2 = df |> mutate($dept = fct($dept) |> fct_reorder($salary))
```

## Pipelines and Polyglot Nodes

A script is executed by building a pipeline:

```t
p = pipeline {
  -- Native T node
  data = node(command = read_csv("data.csv") |> filter($age > 18))
  
  -- R statistical node
  model_r = rn(
    command = <{
      lm(score ~ age + income, data = data)
    }>,
    serializer = "pmml"
  )
  
  -- Python ML node
  model_py = pyn(
    command = <{
      from sklearn.ensemble import RandomForestRegressor
      RandomForestRegressor().fit(X, y)
    }>,
    serializer = "pmml"
  )
  
  -- Native predictions in T using PMML models
  predictions = node(
    command = test_data |> mutate($pred = predict(model_r, test_data))
  )
}

build_pipeline(p)
```

Instead of inlining code with `command`, nodes can point to an external file using the `script` argument. `script` and `command` are mutually exclusive. The runtime is auto-detected from the file extension (`.R` → R, `.py` → Python):

```t
p = pipeline {
  model = rn(script = "train_model.R", serializer = "pmml")
  predictions = pyn(script = "predict.py", deserializer = "pmml")
}
```

Pipeline operations allow composing, transforming, and inspecting pipelines without rebuilding them from scratch:

```t
-- Set operations
p_full = p_etl |> union(p_model)          -- merge (errors on name collision)
p_trimmed = p_full |> difference(p_debug) -- remove nodes by name
p_shared = p1 |> intersect(p2)            -- keep nodes present in both
p_updated = p_prod |> patch(p_overrides)  -- update existing nodes only

-- DAG operations
p2 = p |> swap("model", new_model)        -- replace implementation, keep edges
p2 = p |> rewire("model", replace = list(data = "data_v2"))
p2 = p |> prune                           -- remove leaf nodes
p2 = p |> upstream_of("model")            -- ancestors of a node
p2 = p |> downstream_of("clean")          -- descendants of a node

-- Composition
p_full = p_etl |> chain(p_model)          -- connect two pipelines (requires shared refs)
p_both = parallel(p_r_model, p_py_model)  -- merge independent pipelines

-- Inspection
pipeline_nodes(p)      -- list of node names
pipeline_deps(p)       -- dependency graph as Dict
pipeline_to_frame(p)   -- DataFrame with one row per node
pipeline_dot(p)        -- Graphviz DOT string for visualization

-- Validation
p |> pipeline_validate(p)   -- returns list of errors; never throws
p |> pipeline_assert   -- throws on first error; returns pipeline if valid
```

## Literate Programming (Quarto)

T supports Quarto for generating reports. Quarto nodes are defined using `runtime = Quarto`:

```t
p = pipeline {
  report = node(script = "analysis.qmd", runtime = Quarto)
}
```

Inside `analysis.qmd`, you can use `read_node("node_name")` in R, Python, or Javascript chunks. T will substitute these calls with the absolute paths to the node artifacts in the Nix store.

Use `pipeline_copy()` to copy rendered reports and other artifacts from the Nix store to your local `pipeline-output/` directory.

```t
build_pipeline(p)
pipeline_copy()
```

## Core Standard Library Signatures

### Core & Math
- `print(value :: Any) :: Null`
- `type(value :: Any) :: String`
- `length(list :: List) :: Int`
- `head(x :: DataFrame | List | Vector, n = 6) :: DataFrame | List | Vector`
- `tail(x :: DataFrame | List | Vector, n = 6) :: DataFrame | List | Vector`
- `map(list :: List, fn :: Function) :: List`
- `filter(list :: List, fn :: Function) :: List`
- `sum(list :: List, na_rm = false) :: Number`
- `seq(start = 1, end :: Int, by = 1) :: List[Int]`
- `pow(base :: Number, exp :: Number) :: Float`
- `sqrt(value :: Number) :: Float`
- `abs(value :: Number) :: Number`

### Base
- `is_na(value :: Any) :: Bool`
- `na_int()`, `na_float()`, `na_string()`, `na_bool()`
- `is_error(value :: Any) :: Bool`
- `error(message :: String) :: Error`

### Stats
- `mean(vector :: Vector, na_rm = false) :: Float`
- `sd(vector :: Vector, na_rm = false) :: Float`
- `quantile(vector :: Vector, prob :: Float, na_rm = false) :: Float`
- `cor(v1 :: Vector, v2 :: Vector, na_rm = false) :: Float`
- `lm(data :: DataFrame, formula :: Formula) :: Model`
- `predict(model :: Model, data :: DataFrame) :: Vector`

### DataFrame
- `read_csv(path :: String, clean_colnames = false) :: DataFrame`
- `write_csv(df :: DataFrame, path :: String) :: Null`
- `nrow(df :: DataFrame) :: Int`
- `ncol(df :: DataFrame) :: Int`
- `colnames(df :: DataFrame) :: List[String]`

### Colcraft — Core dplyr-style
- `select(df :: DataFrame, ...) :: DataFrame`
- `filter(df :: DataFrame, predicate :: NSE) :: DataFrame`
- `mutate(df :: DataFrame, ...) :: DataFrame`
- `arrange(df :: DataFrame, $col, direction = "asc") :: DataFrame`
- `group_by(df :: DataFrame, ...) :: DataFrame`
- `summarize(df :: DataFrame, ...) :: DataFrame`
- `rename(df :: DataFrame, $new = $old, ...) :: DataFrame`
- `relocate(df :: DataFrame, ..., .before :: Symbol, .after :: Symbol) :: DataFrame`
- `distinct(df :: DataFrame, ..., .keep_all = false) :: DataFrame`
- `count(df :: DataFrame, ..., name = "n") :: DataFrame`
- `slice(df :: DataFrame, indices :: Vector | List) :: DataFrame`
- `slice_min(df :: DataFrame, order_by :: Symbol, n = 1) :: DataFrame`
- `slice_max(df :: DataFrame, order_by :: Symbol, n = 1) :: DataFrame`

### Colcraft — Reshaping (tidyr-style)
- `pivot_longer(df :: DataFrame, ..., names_to = "name", values_to = "value") :: DataFrame`
- `pivot_wider(df :: DataFrame, names_from :: Symbol, values_from :: Symbol) :: DataFrame`
- `complete(df :: DataFrame, ..., fill = [:], explicit = true) :: DataFrame`
- `expand(df :: DataFrame, ...) :: DataFrame`
- `crossing(...) :: DataFrame`
- `nesting(...) :: Any`

### Colcraft — Strings & Rows
- `separate(df :: DataFrame, $col, into :: List[String], sep = "[^[:alnum:]]+", remove = true) :: DataFrame`
- `unite(df :: DataFrame, col :: String, ..., sep = "_", remove = true) :: DataFrame`
- `separate_rows(df :: DataFrame, $col, sep = "[^A-Za-z0-9]+") :: DataFrame`
- `uncount(df :: DataFrame, $weights, .remove = true) :: DataFrame`

### Colcraft — Multi-table
- `left_join(x :: DataFrame, y :: DataFrame, by = [String]) :: DataFrame`
- `inner_join(x :: DataFrame, y :: DataFrame, by = [String]) :: DataFrame`
- `full_join(x :: DataFrame, y :: DataFrame, by = [String]) :: DataFrame`
- `semi_join(x :: DataFrame, y :: DataFrame, by = [String]) :: DataFrame`
- `anti_join(x :: DataFrame, y :: DataFrame, by = [String]) :: DataFrame`
- `bind_rows(...) :: DataFrame`
- `bind_cols(...) :: DataFrame`

### Colcraft — Missing Values
- `drop_na(df :: DataFrame, ...) :: DataFrame`
- `replace_na(df :: DataFrame, replace :: Dict) :: DataFrame`
- `fill(df :: DataFrame, ..., .direction = "down") :: DataFrame`

### Colcraft — Nested Data
- `nest(df :: DataFrame, ..., name = "data") :: DataFrame`
- `unnest(df :: DataFrame, $col) :: DataFrame`

### Colcraft — Selection Helpers
- `starts_with(prefix :: String) :: List[String]`
- `ends_with(suffix :: String) :: List[String]`
- `contains(pattern :: String) :: List[String]`
- `everything() :: List[String]`
- `where(predicate :: BuiltinFunction) :: List[String]`
- `matches(pattern :: String) :: List[String]`
- `all_of(cols :: List[String] | Vector[String]) :: List[String]`
- `any_of(cols :: List[String] | Vector[String]) :: List[String]`
- `is_numeric(x :: Any) :: Bool`
- `is_character(x :: Any) :: Bool`
- `is_logical(x :: Any) :: Bool`
- `is_factor(x :: Any) :: Bool`

### Colcraft — Factors
- `factor(x :: Vector | List, levels = [], ordered = false) :: Vector`
- `fct(x :: Vector | List, levels = [], ordered = false) :: Vector`
- `ordered(x :: Vector | List, levels :: Vector | List) :: Vector`
- `as_factor(x :: Vector | List) :: Vector`
- `levels(x :: Vector) :: Vector`
- `fct_rev(x :: Vector) :: Vector`
- `fct_recode(x :: Vector, $new = $old, ...) :: Vector`
- `fct_reorder(f :: Vector, x :: Vector, .desc = false) :: Vector`
- `fct_relevel(f :: Vector, ..., after = 0) :: Vector`
- `fct_lump_n(x :: Vector, n = 10, other_level = "Other") :: Vector`
- `fct_lump_min(x :: Vector, min :: Int, other_level = "Other") :: Vector`
- `fct_lump_prop(x :: Vector, prop :: Float, other_level = "Other") :: Vector`
- `fct_infreq(x :: Vector) :: Vector`
- `fct_collapse(x :: Vector, new_level = [$old1, ...], ...) :: Vector`
- `fct_other(x :: Vector, keep = [], drop = [], other_level = "Other") :: Vector`
- `fct_drop(x :: Vector) :: Vector`
- `fct_expand(x :: Vector, ...) :: Vector`
- `fct_c(... :: Vector) :: Vector`

### Chrono
- `make_date(year = 1970, month = 1, day = 1) :: Date`
- `make_datetime(year = 1970, month = 1, day = 1, hour = 0, min = 0, sec = 0, tz = "UTC") :: Datetime`
- `am(x :: Date | Datetime) :: Bool`
- `pm(x :: Date | Datetime) :: Bool`
- `interval(start :: Date | Datetime, end :: Date | Datetime) :: Interval`
- `` `%within%`(x :: Date | Datetime, iv :: Interval) :: Bool ``
- `floor_date(x :: Date | Datetime, unit :: String) :: Date | Datetime`
- `ceiling_date(x :: Date | Datetime, unit :: String) :: Date | Datetime`
- `round_date(x :: Date | Datetime, unit :: String) :: Date | Datetime`
- `with_tz(x :: Datetime, tz :: String) :: Datetime` (label-only in current implementation)
- `force_tz(x :: Datetime, tz :: String) :: Datetime` (label-only in current implementation)
- `is_leap_year(x :: Int | Date | Datetime) :: Bool`
- `days_in_month(x :: Int, m :: Int) :: Int`

### Colcraft — Window Functions
- `row_number(x :: Vector) :: Vector`
- `min_rank(x :: Vector) :: Vector`
- `dense_rank(x :: Vector) :: Vector`
- `percent_rank(x :: Vector) :: Vector`
- `cume_dist(x :: Vector) :: Vector`
- `ntile(x :: Vector, n :: Int) :: Vector`
- `cumsum(x :: Vector) :: Vector`
- `cummin(x :: Vector) :: Vector`
- `cummax(x :: Vector) :: Vector`
- `cummean(x :: Vector, na_rm = false) :: Vector`
- `cumall(x :: Vector) :: Vector`
- `cumany(x :: Vector) :: Vector`
- `lag(x :: Vector, n = 1) :: Vector`
- `lead(x :: Vector, n = 1) :: Vector`

### Pipeline

#### Node Constructors
- `node(command :: Any, script :: String, runtime = "T", serializer = "default", deserializer = "default", functions = [], include = [], noop = false) :: Any`
- `pyn(command :: Any, script :: String, serializer = "default", deserializer = "default", functions = [], include = [], noop = false) :: Any`
- `rn(command :: Any, script :: String, serializer = "default", deserializer = "default", functions = [], include = [], noop = false) :: Any`

`command` and `script` are mutually exclusive. When `script` is used, the runtime is auto-detected from the file extension (`.R` → R, `.py` → Python) if not set explicitly.

#### Execution
- `populate_pipeline(pipeline :: Pipeline, build = false) :: Null`
- `build_pipeline(pipeline :: Pipeline) :: Null`
- `pipeline_run(pipeline :: Pipeline) :: Pipeline`

#### Inspection
- `pipeline_nodes(p :: Pipeline) :: List[String]`
- `pipeline_deps(p :: Pipeline) :: Dict`
- `pipeline_to_frame(p :: Pipeline) :: DataFrame`
- `pipeline_edges(p :: Pipeline) :: List[List[String]]`
- `pipeline_roots(p :: Pipeline) :: List[String]`
- `pipeline_leaves(p :: Pipeline) :: List[String]`
- `pipeline_depth(p :: Pipeline) :: Int`
- `pipeline_cycles(p :: Pipeline) :: List[String]`
- `pipeline_print(p :: Pipeline) :: Null`
- `pipeline_dot(p :: Pipeline) :: String`
- `read_node(name :: String, which_log = null) :: Any`

#### Validation
- `pipeline_validate(p :: Pipeline) :: List[String]`
- `pipeline_assert(p :: Pipeline) :: Pipeline`

#### Node Manipulation
- `filter_node(p :: Pipeline, predicate :: Function) :: Pipeline`
- `mutate_node(p :: Pipeline, ..., where :: Function) :: Pipeline`
- `rename_node(p :: Pipeline, old_name :: String, new_name :: String) :: Pipeline`
- `select_node(p :: Pipeline, ...) :: DataFrame`
- `arrange_node(p :: Pipeline, field :: Symbol, direction = "asc") :: Pipeline`

#### Set Operations
- `union(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`
- `difference(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`
- `intersect(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`
- `patch(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`

#### DAG-Aware Transformations
- `swap(p :: Pipeline, name :: String, new_node :: Node) :: Pipeline`
- `rewire(p :: Pipeline, name :: String, replace :: List[String]) :: Pipeline`
- `prune(p :: Pipeline) :: Pipeline`
- `upstream_of(p :: Pipeline, name :: String) :: Pipeline`
- `downstream_of(p :: Pipeline, name :: String) :: Pipeline`
- `subgraph(p :: Pipeline, name :: String) :: Pipeline`

#### Composition
- `chain(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`
- `parallel(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`

## Metaprogramming
- `expr(code)`: Quotation block capturing code as an AST.
- `!!value`: Unquote single value into `expr`.
- `!!!list`: Unquote-splice a list into `expr`.
- `eval(expr)`: Evaluates a quoted expression.
