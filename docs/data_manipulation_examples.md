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

---

## select() — Choose Columns

Select keeps only the specified columns:

```t
-- Select two columns
df |> select("name", "age")
-- DataFrame(100 rows x 2 cols: [name, age])

-- Select a single column
df |> select("name")
-- DataFrame(100 rows x 1 cols: [name])
```

**Error handling:**
```t
df |> select("nonexistent")
-- Error(KeyError: "Column(s) not found: nonexistent")

df |> select(42)
-- Error(TypeError: "select() expects string column names")
```

---

## filter() — Choose Rows

Filter keeps rows where a predicate returns true:

```t
-- Keep employees older than 30
df |> filter(\(row) row.age > 30)

-- Keep engineering department
df |> filter(\(row) row.dept == "eng")

-- Combine with pipe
df |> filter(\(row) row.dept == "eng") |> nrow
-- 42 (number of engineers)
```

The predicate receives each row as a record with dot-access to columns.

---

## mutate() — Add or Transform Columns

Mutate adds a new column or replaces an existing one:

```t
-- Add a new column
df |> mutate("age_plus_10", \(row) row.age + 10)
-- DataFrame with new column 'age_plus_10'

-- Replace an existing column
df |> mutate("age", \(row) row.age + 1)
-- DataFrame with updated 'age' column (same column count)
```

**Error handling:**
```t
mutate(42, "x", \(r) r)
-- Error(TypeError: "mutate() expects a DataFrame as first argument")

df |> mutate(42, \(r) r)
-- Error(TypeError: "mutate() expects a string column name as second argument")
```

---

## arrange() — Sort Rows

Arrange sorts a DataFrame by a column:

```t
-- Sort ascending (default)
df |> arrange("age")

-- Sort descending
df |> arrange("age", "desc")

-- Verify sort order
df |> arrange("age") |> select("name") |> \(d) d.name
-- Vector sorted by age
```

**Error handling:**
```t
df |> arrange("nonexistent")
-- Error(KeyError: "Column 'nonexistent' not found in DataFrame")

df |> arrange("age", "up")
-- Error(ValueError: "arrange() direction must be "asc" or "desc"")
```

---

## group_by() — Group Rows

Group creates a grouped DataFrame for subsequent summarization:

```t
df |> group_by("dept")
-- DataFrame(100 rows x 5 cols: [...]) grouped by [dept]
```

Grouping is a marker — it doesn't change the data, but tells `summarize()` and `mutate()` how to split the computation.

**Error handling:**
```t
df |> group_by("nonexistent")
-- Error(KeyError: "Column(s) not found: nonexistent")

df |> group_by(42)
-- Error(TypeError: "group_by() expects string column names")
```

---

## summarize() — Aggregate Data

Summarize computes aggregate statistics:

### Ungrouped Summarize

```t
df |> summarize("total_rows", \(d) nrow(d))
-- DataFrame(1 rows x 1 cols: [total_rows])
```

### Grouped Summarize

```t
df |> group_by("dept")
   |> summarize("count", \(g) nrow(g))
-- DataFrame(N rows x 2 cols: [dept, count])
-- One row per group
```

---

## Grouped Mutate — Group-Wise Transformations

When `mutate()` is applied to a grouped DataFrame, the function receives the group sub-DataFrame instead of a single row. The result is broadcast to every row in that group:

```t
-- Add group size to each row
df |> group_by("dept")
   |> mutate("dept_size", \(g) nrow(g))
-- Each row gets the count of its group

-- Compute group mean and broadcast
df |> group_by("dept")
   |> mutate("mean_score", \(g) mean(g.score))
-- Each row gets the mean score of its department
```

### Common Patterns

```t
-- Chain grouped mutate with filter
df |> group_by("dept")
   |> mutate("dept_size", \(g) nrow(g))
   |> filter(\(row) row.dept_size > 2)
-- Keep only rows from large departments
```

**Note:** Grouped mutate preserves the group keys on the resulting DataFrame.

---

## Composing Verbs

The real power is in composing verbs with the pipe operator:

### Example 1: Filter, Select, and Count

```t
df |> filter(\(row) row.age > 25)
   |> select("name", "score")
   |> nrow
```

### Example 2: Mutate and Filter

```t
df |> mutate("senior", \(row) row.age >= 30)
   |> filter(\(row) row.senior == true)
   |> nrow
```

### Example 3: Complete Tidy Pipeline

```t
df |> filter(\(row) row.age > 25)
   |> select("name", "score")
   |> arrange("score", "desc")
   |> nrow
```

### Example 4: Group and Summarize

```t
result = df
  |> group_by("dept")
  |> summarize("count", \(g) nrow(g))

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
  clean = raw |> filter(\(row) row.amount > 0)
  
  -- Analyze by region
  by_region = clean
    |> group_by("region")
    |> summarize("total", \(g) sum(g.amount))
  
  -- Sort results
  ranked = by_region |> arrange("total", "desc")
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
