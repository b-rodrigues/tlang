# Data Manipulation Examples

> Practical examples of data wrangling with T's core verbs

T provides six core data manipulation functions in the `colcraft` package: `select()`, `filter()`, `mutate()`, `arrange()`, `group_by()`, and `summarize()`. All functions take a DataFrame as their first argument and return a new DataFrame, making them composable with the pipe operator.

---

## Loading Data

```t
df = read_csv("employees.csv")
-- DataFrame(100 rows x 5 cols: [name, age, score, dept, salary])

nrow(df)      -- 100
ncol(df)      -- 5
colnames(df)  -- ["name", "age", "score", "dept", "salary"]
```

### read_csv() Options

```t
-- Custom separator (e.g., semicolon-delimited files)
df = read_csv("data.tsv", separator = ";")

-- Skip comment lines at the top of a file
df = read_csv("data_with_header.csv", skip_lines = 2)

-- No header row (columns named V1, V2, ...)
df = read_csv("raw_data.csv", skip_header = true)

-- Normalize column names to safe snake_case identifiers
df = read_csv("messy_headers.csv", clean_colnames = true)
```

### Column Name Cleaning

The `clean_colnames` option (or standalone function) normalizes column names:

```t
-- As a read_csv option
df = read_csv("data.csv", clean_colnames = true)
-- "Growth%"  → "growth_percent"
-- "MILLION€" → "million_euro"
-- "café"     → "cafe"
-- "A.1"      → "a_1"

-- As a standalone function on a DataFrame
df2 = clean_colnames(df)

-- On a list of strings
clean_colnames(["A.1", "A-1"])  -- ["a_1", "a_1_2"]
```

Duplicate names after cleaning are disambiguated: the first occurrence stays unchanged, subsequent duplicates get `_2`, `_3`, etc.


---

## Creating DataFrames

You can create DataFrames manually from a list of rows using the `dataframe()` function. Each row can be a Dict or a named List.

```t
-- From a list of named Lists (idiomatic row constructor)
df = dataframe([
  [name: "Alice", age: 30, score: 88.5],
  [name: "Bob",   age: 25, score: 92.0]
])

-- DataFrame(2 rows x 3 cols: [name, age, score])
```

This is particularly useful for:
- Creating lookup tables
- Writing test cases
- Entering small datasets manually


## Saving Data

```t
-- Save a DataFrame to CSV
write_csv(df, "output.csv")

-- Save with a custom separator
write_csv(df, "output.tsv", separator = "\t")
```

---

## select() — Choose Columns

Select keeps only the specified columns:

```t
df |> select($name, $age)
-- DataFrame(100 rows x 2 cols: [name, age])

df |> select($name)
-- DataFrame(100 rows x 1 cols: [name])
```

**Error handling:**
```t
df |> select($nonexistent)
-- Error(KeyError: "Column(s) not found: nonexistent")

df |> select(42)
-- Error(TypeError: "select() expects $column syntax")
```

---

## filter() — Choose Rows

Filter keeps rows where a predicate returns true:

```t
df |> filter($age > 30)
df |> filter($dept == "eng")

-- Combine with pipe
df |> filter($dept == "eng") |> nrow
-- 42 (number of engineers)
```

The NSE syntax auto-transforms `$age > 30` into `\(row) row.age > 30`.

---

## mutate() — Add or Transform Columns

Mutate adds a new column or replaces an existing one:

```t
-- Named-arg NSE syntax: $col = NSE expression
df |> mutate($age_plus_10 = $age + 10)
df |> mutate($bonus = $salary * 0.1)

-- Positional NSE for column name with explicit lambda
df |> mutate($age_plus_10, \(row) row.age + 10)
```

**Error handling:**
```t
mutate(42, $x, \(r) r)
-- Error(TypeError: "mutate() expects a DataFrame as first argument")

df |> mutate(42, \(r) r)
-- Error(TypeError: "mutate() expects $column = expr syntax")
```

---

## arrange() — Sort Rows

Arrange sorts a DataFrame by a column:

```t
df |> arrange($age)
df |> arrange($age, "desc")
```

**Error handling:**
```t
df |> arrange($nonexistent)
-- Error(KeyError: "Column 'nonexistent' not found in DataFrame")

df |> arrange($age, "up")
-- Error(ValueError: "arrange() direction must be "asc" or "desc"")
```

---

## group_by() — Group Rows

Group creates a grouped DataFrame for subsequent summarization:

```t
df |> group_by($dept)
-- DataFrame(100 rows x 5 cols: [...]) grouped by [dept]
```

Grouping is a marker — it doesn't change the data, but tells `summarize()` and `mutate()` how to split the computation.

**Error handling:**
```t
df |> group_by($nonexistent)
-- Error(KeyError: "Column(s) not found: nonexistent")

df |> group_by(42)
-- Error(TypeError: "group_by() expects $column syntax")
```

---

## summarize() — Aggregate Data

Summarize computes aggregate statistics:

### Ungrouped Summarize

```t
-- Named-arg NSE syntax: $col = NSE aggregation
df |> summarize($total_score = sum($score))

-- Positional NSE with lambda
df |> summarize($total_rows, \(d) nrow(d))
-- DataFrame(1 rows x 1 cols: [total_rows])
```

### Grouped Summarize

```t
-- Named-arg NSE syntax
df |> group_by($dept)
   |> summarize($count = nrow($dept), $avg_score = mean($score))

-- Positional NSE with lambda
df |> group_by($dept)
   |> summarize($count, \(g) nrow(g))
-- DataFrame(N rows x 2 cols: [dept, count])
-- One row per group
```

---

## Grouped Mutate — Group-Wise Transformations

When `mutate()` is applied to a grouped DataFrame, the function receives the group sub-DataFrame instead of a single row. The result is broadcast to every row in that group:

```t
-- Add group size to each row
df |> group_by($dept)
   |> mutate($dept_size, \(g) nrow(g))

-- Compute group mean and broadcast
df |> group_by($dept)
   |> mutate($mean_score, \(g) mean(g.score))
```

### Common Patterns

```t
-- Chain grouped mutate with filter
df |> group_by($dept)
   |> mutate($dept_size, \(g) nrow(g))
   |> filter($dept_size > 2)
-- Keep only rows from large departments
```

**Note:** Grouped mutate preserves the group keys on the resulting DataFrame.

---

## Composing Verbs

The real power is in composing verbs with the pipe operator:

### Example 1: Filter, Select, and Count

```t
df |> filter($age > 25)
   |> select($name, $score)
   |> nrow
```

### Example 2: Mutate and Filter

```t
df |> mutate($senior, \(row) row.age >= 30)
   |> filter($senior == true)
   |> nrow
```

### Example 3: Complete Tidy Pipeline

```t
df |> filter($age > 25)
   |> select($name, $score)
   |> arrange($score, "desc")
   |> nrow
```

### Example 4: Group and Summarize

```t
result = df
  |> group_by($dept)
  |> summarize($count, \(g) nrow(g))

result.dept    -- Vector of department names
result.count   -- Vector of counts per department
```

---

## Error Recovery with Maybe-Pipe

When working with data pipelines, operations can fail (missing files, invalid data, etc.). The maybe-pipe `?|>` forwards errors to a recovery function instead of short-circuiting:

### Pattern 1: Default Value on Error

```t
-- Normal pipe short-circuits on error:
error("missing") |> \(x) x + 1   -- Error (never calls function)

-- Maybe-pipe forwards the error:
with_default = \(x) if (is_error(x)) 0 else x
error("missing") ?|> with_default  -- 0
```

### Pattern 2: Recovery in Data Pipelines

```t
-- Provide fallback values for errors
with_default = \(result) if (is_error(result)) 0 else result

value1 = 5 ?|> with_default                    -- 5
value2 = error("missing data") ?|> with_default -- 0
```

### Pattern 3: Mixed Pipe Chain

```t
recovery = \(x) if (is_error(x)) 0 else x
increment = \(x) x + 1

-- ?|> forwards error to recovery, then |> continues normally
error("fail") ?|> recovery |> increment   -- 1
```

---

## Using Math and Stats

Math and stats functions work on DataFrame columns:

```t
-- Column statistics
mean(df.salary)          -- mean salary
sd(df.salary)            -- salary standard deviation
quantile(df.score, 0.5)  -- median score

-- Column transformations
sqrt(df.score)     -- Vector of sqrt values
abs(df.balance)    -- Vector of absolute values
```

### Handling Missing Values in Statistics

By default, aggregation functions **error** when encountering NA values, forcing explicit handling. Use `na_rm = true` to skip NA values:

```t
-- Default: errors on NA (forces explicit handling)
mean(df.salary)                      -- Error if any salary is NA

-- Skip NA values with na_rm = true
mean(df.salary, na_rm = true)        -- mean of non-NA salaries
sum(df.amount, na_rm = true)         -- sum of non-NA amounts
sd(df.score, na_rm = true)           -- sd of non-NA scores
quantile(df.age, 0.5, na_rm = true)  -- median of non-NA ages
cor(df.x, df.y, na_rm = true)        -- correlation with pairwise deletion
```

### Linear Regression

```t
model = lm(data = df, formula = salary ~ age)
model.slope       -- coefficient
model.intercept   -- intercept
model.r_squared   -- R² goodness of fit
model.n           -- number of observations
```

---

## Using Pipelines for Analysis

For complex analyses, wrap your workflow in a pipeline for structure and caching:

```t
p = pipeline {
  raw = read_csv("sales.csv")
  
  -- Clean
  clean = raw |> filter($amount > 0)
  
  -- Analyze by region
  by_region = clean
    |> group_by($region)
    |> summarize($total, \(g) sum(g.amount))
  
  -- Sort results
  ranked = by_region |> arrange($total, "desc")
}

p.ranked  -- regions ranked by total sales
```

---

## Introspection with explain()

Use `explain()` to get structured metadata about any value:

```t
e = explain(df)
e.kind        -- "dataframe"
e.nrow        -- number of rows
e.ncol        -- number of columns
e.schema      -- column type information
e.na_stats    -- NA counts per column
e.example_rows -- sample rows
```

---

## Window Functions

Window functions operate on vectors without collapsing them, useful for ranking, shifting, and cumulative calculations.

### Ranking

```t
-- Rank values (ties broken by position)
row_number([10, 30, 20])    -- Vector[1, 3, 2]

-- Rank with ties (minimum rank, with gaps)
min_rank([1, 1, 2, 2, 2])  -- Vector[1, 1, 3, 3, 3]

-- Dense rank (no gaps)
dense_rank([1, 1, 2, 2])   -- Vector[1, 1, 2, 2]

-- Divide into n groups
ntile([1, 2, 3, 4, 5, 6], 3)  -- Vector[1, 1, 2, 2, 3, 3]
```

### Lag and Lead

```t
-- Previous value (lagged by 1)
lag([10, 20, 30, 40])       -- Vector[NA, 10, 20, 30]

-- Next value (lead by 1)
lead([10, 20, 30, 40])      -- Vector[20, 30, 40, NA]

-- Custom offset
lag([10, 20, 30, 40], 2)    -- Vector[NA, NA, 10, 20]
```

### Cumulative Functions

```t
cumsum([1, 2, 3, 4])        -- Vector[1, 3, 6, 10]
cummin([5, 3, 4, 1])        -- Vector[5, 3, 3, 1]
cummax([1, 3, 2, 5])        -- Vector[1, 3, 3, 5]
cummean([2, 4, 6])           -- Vector[2.0, 3.0, 4.0]
```

### NA Handling in Window Functions

All window functions handle NA values gracefully:

- **Ranking functions**: NA positions receive NA rank; ranks are computed only among non-NA values
- **Offset functions (lag/lead)**: NA values pass through unchanged
- **Cumulative functions**: NA propagates to all subsequent values (matching R behavior)

```t
-- Ranking with NA
row_number([3, NA, 1])      -- Vector[2, NA, 1]
min_rank([3, NA, 1, 3])    -- Vector[2, NA, 1, 2]

-- Cumulative with NA (propagation)
cumsum([1, NA, 3])           -- Vector[1, NA, NA]
cummax([1, NA, 5])           -- Vector[1, NA, NA]
```
