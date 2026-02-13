# API Reference

Complete reference for all functions in T's standard library.

> **Version**: Alpha 0.1  
> **Auto-loaded**: All packages are automatically available in every T session

---

## Table of Contents

- [Core Package](#core-package) — Basic functional utilities
- [Base Package](#base-package) — Errors, NA, assertions
- [Math Package](#math-package) — Mathematical functions
- [Stats Package](#stats-package) — Statistical functions
- [DataFrame Package](#dataframe-package) — CSV I/O and DataFrame operations
- [Colcraft Package](#colcraft-package) — Data manipulation verbs and window functions
- [Pipeline Package](#pipeline-package) — Pipeline introspection
- [Explain Package](#explain-package) — Introspection and debugging tools

---

## Core Package

Fundamental functional programming utilities.

### `print(value)`

Print a value to standard output.

**Parameters:**
- `value` — Any value to print

**Returns:** The printed value (for chaining)

**Examples:**
```t
print(42)                    -- 42
print("Hello, T!")           -- Hello, T!
print([1, 2, 3])             -- [1, 2, 3]
x = 10 |> print |> \(v) v * 2  -- Prints 10, returns 20
```

---

### `pretty_print(value)`

Pretty-print a value with detailed formatting (for DataFrames, structures, etc.).

**Parameters:**
- `value` — Any value

**Returns:** The value (for chaining)

**Examples:**
```t
pretty_print(df)  -- Formatted DataFrame output
```

---

### `type(value)`

Get the type name of a value as a string.

**Parameters:**
- `value` — Any value

**Returns:** `String` — Type name

**Examples:**
```t
type(42)             -- "Int"
type(3.14)           -- "Float"
type(true)           -- "Bool"
type("hello")        -- "String"
type([1, 2])         -- "List"
type({x: 1})         -- "Dict"
type(NA)             -- "NA"
type(error("x"))     -- "Error"
type(df)             -- "DataFrame"
```

---

### `length(collection)`

Get the number of elements in a collection.

**Parameters:**
- `collection` — List, Vector, or String

**Returns:** `Int` — Number of elements

**Examples:**
```t
length([1, 2, 3])      -- 3
length("hello")        -- 5
length([])             -- 0
```

---

### `head(collection, n)`

Get the first element(s) of a collection. For DataFrames, returns the first `n` rows (default 5). For Lists, returns the first element.

**Parameters:**
- `collection` — List or DataFrame
- `n` (optional) — Number of rows for DataFrames (default: 5); not used for Lists

**Returns:** Single element (for Lists) or DataFrame (for DataFrames)

**Examples:**
```t
head([1, 2, 3, 4, 5])       -- 1
head(df)                     -- first 5 rows
head(df, 3)                  -- first 3 rows
head(df, n = 10)             -- first 10 rows
```

---

### `tail(collection, n)`

For DataFrames, returns the last `n` rows (default 5). For Lists, returns all elements except the first.

**Parameters:**
- `collection` — List or DataFrame
- `n` (optional) — Number of rows for DataFrames (default: 5); not used for Lists

**Returns:** List (for Lists) or DataFrame (for DataFrames)

**Examples:**
```t
tail([1, 2, 3, 4, 5])  -- [2, 3, 4, 5]
tail(df)                -- last 5 rows
tail(df, 3)             -- last 3 rows
tail(df, n = 10)        -- last 10 rows
```

---

### `map(collection, fn)`

Apply a function to each element of a collection.

**Parameters:**
- `collection` — List or Vector
- `fn` — Function to apply: `\(x) ...`

**Returns:** List (or Vector) of results

**Examples:**
```t
map([1, 2, 3], \(x) x * x)           -- [1, 4, 9]
map(["a", "b"], \(s) s + "!")        -- ["a!", "b!"]
map([1, 2, 3], \(x) x + 10)          -- [11, 12, 13]
```

---

### `filter(collection, predicate)`

Keep only elements that satisfy a predicate.

**Parameters:**
- `collection` — List or Vector
- `predicate` — Function returning Bool: `\(x) ...`

**Returns:** List (or Vector) of matching elements

**Examples:**
```t
filter([1, 2, 3, 4, 5], \(x) x > 3)    -- [4, 5]
filter([1, 2, 3], \(x) x % 2 == 0)     -- [2]
filter(["a", "ab", "abc"], \(s) length(s) > 1)  -- ["ab", "abc"]
```

---

### `sum(collection)`

Sum all numeric elements.

**Parameters:**
- `collection` — List or Vector of numbers

**Returns:** `Int` or `Float` — Sum

**Examples:**
```t
sum([1, 2, 3, 4, 5])    -- 15
sum([1.5, 2.5, 3.0])    -- 7.0
sum([])                 -- 0
```

---

### `seq(start, end, step = 1)`

Generate a sequence of numbers.

**Parameters:**
- `start` — Starting value
- `end` — Ending value (inclusive)
- `step` (optional) — Increment (default: 1)

**Returns:** List of numbers

**Examples:**
```t
seq(1, 5)       -- [1, 2, 3, 4, 5]
seq(0, 10, 2)   -- [0, 2, 4, 6, 8, 10]
seq(5, 1, -1)   -- [5, 4, 3, 2, 1]
```

---

### `is_error(value)`

Check if a value is an error.

**Parameters:**
- `value` — Any value

**Returns:** `Bool` — true if value is an Error

**Examples:**
```t
is_error(42)             -- false
is_error(error("msg"))   -- true
is_error(1 / 0)          -- true
```

---

## Base Package

Error handling, NA values, and assertions.

### `error(message)` / `error(code, message)`

Create an error value.

**Parameters:**
- `message` — Error message string
- `code` (optional) — Error code string

**Returns:** `Error` value

**Examples:**
```t
error("Something went wrong")
error("ValueError", "Invalid input")

e = error("custom error")
error_message(e)  -- "custom error"
```

---

### `is_error(value)`

Check if a value is an error (see Core package).

---

### `error_code(err)`

Get the error code from an Error value.

**Parameters:**
- `err` — Error value

**Returns:** `String` — Error code

**Examples:**
```t
e = 1 / 0
error_code(e)  -- "DivisionByZero"

e2 = error("TypeError", "msg")
error_code(e2)  -- "TypeError"
```

---

### `error_message(err)`

Get the error message from an Error value.

**Parameters:**
- `err` — Error value

**Returns:** `String` — Error message

**Examples:**
```t
e = error("Something broke")
error_message(e)  -- "Something broke"

e2 = 1 / 0
error_message(e2)  -- "Division by zero"
```

---

### `error_context(err)`

Get additional context from an Error value (if available).

**Parameters:**
- `err` — Error value

**Returns:** `String` — Context information

**Examples:**
```t
error_context(e)  -- Additional debugging information
```

---

### `assert(condition)` / `assert(condition, message)`

Assert that a condition is true; error if false.

**Parameters:**
- `condition` — Boolean expression
- `message` (optional) — Custom error message

**Returns:** `true` if condition holds

**Examples:**
```t
assert(2 + 2 == 4)                -- true
assert(1 > 2)                     -- Error(AssertionError)
assert(false, "Custom message")   -- Error(AssertionError: Custom message)
```

---

### `NA`

Untyped missing value constant.

**Examples:**
```t
x = NA
is_na(x)  -- true
```

---

### `na_int()` / `na_float()` / `na_bool()` / `na_string()`

Create typed NA values.

**Returns:** Typed NA value

**Examples:**
```t
na_int()     -- NA(Int)
na_float()   -- NA(Float)
na_bool()    -- NA(Bool)
na_string()  -- NA(String)
```

---

### `is_na(value)`

Check if a value is NA.

**Parameters:**
- `value` — Any value

**Returns:** `Bool` — true if value is NA

**Examples:**
```t
is_na(NA)           -- true
is_na(na_int())     -- true
is_na(42)           -- false
is_na(null)         -- false (null ≠ NA)
```

---

## Math Package

Mathematical functions operating on scalars and vectors.

### `sqrt(x)`

Square root.

**Parameters:**
- `x` — Number (Int or Float)

**Returns:** `Float`

**Examples:**
```t
sqrt(4)      -- 2.0
sqrt(2)      -- 1.41421356237
sqrt(0)      -- 0.0
sqrt(-1)     -- Error (negative input)
```

---

### `abs(x)`

Absolute value.

**Parameters:**
- `x` — Number

**Returns:** Same type as input

**Examples:**
```t
abs(-5)      -- 5
abs(3.14)    -- 3.14
abs(0)       -- 0
```

---

### `log(x)`

Natural logarithm (base e).

**Parameters:**
- `x` — Number (must be > 0)

**Returns:** `Float`

**Examples:**
```t
log(10)      -- 2.30258509299
log(1)       -- 0.0
log(2.71828) -- 1.0 (approximately)
log(0)       -- Error (log of zero)
log(-1)      -- Error (log of negative)
```

---

### `exp(x)`

Exponential function (e^x).

**Parameters:**
- `x` — Number

**Returns:** `Float`

**Examples:**
```t
exp(0)       -- 1.0
exp(1)       -- 2.71828182846
exp(2)       -- 7.38905609893
```

---

### `pow(base, exponent)`

Power function (base^exponent).

**Parameters:**
- `base` — Number
- `exponent` — Number

**Returns:** `Float`

**Examples:**
```t
pow(2, 3)    -- 8.0
pow(10, 2)   -- 100.0
pow(4, 0.5)  -- 2.0 (square root)
pow(2, -1)   -- 0.5
```

---

### `min(x, y)` / `min(collection)`

Minimum value.

**Parameters:**
- `x, y` — Two numbers, OR
- `collection` — List or Vector

**Returns:** Minimum value

**Examples:**
```t
min(3, 7)           -- 3
min([5, 2, 9, 1])   -- 1
min([])             -- Error
```

---

### `max(x, y)` / `max(collection)`

Maximum value.

**Parameters:**
- `x, y` — Two numbers, OR
- `collection` — List or Vector

**Returns:** Maximum value

**Examples:**
```t
max(3, 7)           -- 7
max([5, 2, 9, 1])   -- 9
max([])             -- Error
```

---

## Stats Package

Statistical functions for data analysis.

### `mean(collection, na_rm = false)`

Arithmetic mean (average).

**Parameters:**
- `collection` — List or Vector of numbers
- `na_rm` (optional) — If true, skip NA values (default: false)

**Returns:** `Float` — Mean value

**Examples:**
```t
mean([1, 2, 3, 4, 5])              -- 3.0
mean([10, 20, 30])                 -- 20.0
mean([1, 2, NA, 4])                -- Error (NA encountered)
mean([1, 2, NA, 4], na_rm = true)  -- 2.33333333333
mean([NA, NA], na_rm = true)       -- NA(Float)
```

---

### `sd(collection, na_rm = false)`

Standard deviation (sample).

**Parameters:**
- `collection` — List or Vector of numbers
- `na_rm` (optional) — If true, skip NA values (default: false)

**Returns:** `Float` — Standard deviation

**Examples:**
```t
sd([2, 4, 4, 4, 5, 5, 7, 9])       -- 2.1380899353
sd([1, 2, 3])                       -- 1.0
sd([1, NA, 3], na_rm = true)        -- 1.41421356237
sd([5, 5, 5])                       -- 0.0 (no variation)
```

---

### `quantile(collection, p, na_rm = false)`

Compute quantile/percentile.

**Parameters:**
- `collection` — List or Vector of numbers
- `p` — Probability (0.0 to 1.0)
- `na_rm` (optional) — If true, skip NA values (default: false)

**Returns:** `Float` — Quantile value

**Examples:**
```t
quantile([1, 2, 3, 4, 5], 0.5)     -- 3.0 (median)
quantile([1, 2, 3, 4, 5], 0.25)    -- 2.0 (Q1)
quantile([1, 2, 3, 4, 5], 0.75)    -- 4.0 (Q3)
quantile([1, NA, 3], 0.5, na_rm = true)  -- 2.0
```

---

### `cor(x, y, na_rm = false)`

Pearson correlation coefficient.

**Parameters:**
- `x` — List or Vector of numbers
- `y` — List or Vector of numbers (same length as x)
- `na_rm` (optional) — If true, use pairwise deletion for NA (default: false)

**Returns:** `Float` — Correlation (-1.0 to 1.0)

**Examples:**
```t
cor([1, 2, 3], [2, 4, 6])                  -- 1.0 (perfect positive)
cor([1, 2, 3], [3, 2, 1])                  -- -1.0 (perfect negative)
cor([1, 2, 3], [4, 5, 6])                  -- 1.0
cor([1, NA, 3], [2, 4, NA], na_rm = true)  -- 1.0 (uses [1,3] and [2,4])
```

---

### `lm(data, formula)`

Linear regression model (ordinary least squares).

**Parameters:**
- `data` — DataFrame
- `formula` — Formula object (`y ~ x`)

**Returns:** Model object with fields:
- `slope` — Regression slope
- `intercept` — Regression intercept
- `r_squared` — R² coefficient of determination
- `n` — Number of observations

**Examples:**
```t
model = lm(data = df, formula = sales ~ advertising)
model.slope        -- e.g., 0.75
model.intercept    -- e.g., 100.0
model.r_squared    -- e.g., 0.82 (82% variance explained)
model.n            -- e.g., 50

-- Use for prediction (manually)
predict = \(x) model.intercept + model.slope * x
predict(200)  -- Predicted sales for advertising = 200
```

---

## DataFrame Package

CSV I/O and DataFrame introspection.

### `read_csv(path, separator = ",", skip_lines = 0, skip_header = false, clean_colnames = false)`

Read a CSV file into a DataFrame.

**Parameters:**
- `path` — File path (String)
- `separator` (optional) — Column separator (default: ",")
- `skip_lines` (optional) — Number of lines to skip at start (default: 0)
- `skip_header` (optional) — If true, treat first row as data (default: false)
- `clean_colnames` (optional) — If true, normalize column names (default: false)

**Returns:** `DataFrame`

**Examples:**
```t
df = read_csv("data.csv")
df = read_csv("data.tsv", separator = "\t")
df = read_csv("data.csv", skip_lines = 2)
df = read_csv("messy.csv", clean_colnames = true)
```

---

### `write_csv(dataframe, path, separator = ",")`

Write a DataFrame to a CSV file.

**Parameters:**
- `dataframe` — DataFrame to write
- `path` — Output file path (String)
- `separator` (optional) — Column separator (default: ",")

**Returns:** `null`

**Examples:**
```t
write_csv(df, "output.csv")
write_csv(df, "output.tsv", separator = "\t")
```

---

### `nrow(dataframe)`

Get number of rows.

**Parameters:**
- `dataframe` — DataFrame

**Returns:** `Int` — Row count

**Examples:**
```t
nrow(df)  -- 100
```

---

### `ncol(dataframe)`

Get number of columns.

**Parameters:**
- `dataframe` — DataFrame

**Returns:** `Int` — Column count

**Examples:**
```t
ncol(df)  -- 5
```

---

### `colnames(dataframe)`

Get column names.

**Parameters:**
- `dataframe` — DataFrame

**Returns:** List of Strings

**Examples:**
```t
colnames(df)  -- ["name", "age", "dept", "salary"]
```

---

### `glimpse(dataframe)`

Get a compact overview of a DataFrame, showing column names, types, and example values. Similar to dplyr's `glimpse()`.

**Parameters:**
- `dataframe` — DataFrame

**Returns:** Dict with `kind`, `nrow`, `ncol`, and `columns` (list of column summaries)

**Examples:**
```t
glimpse(df)
-- {`kind`: "dataframe", `nrow`: 100, `ncol`: 4, `columns`: ["name <String> ...", "age <Int> ...", ...]}
```

---

### `clean_colnames(dataframe)` / `clean_colnames(names)`

Normalize column names to safe identifiers.

**Parameters:**
- `dataframe` — DataFrame, OR
- `names` — List of Strings

**Returns:** DataFrame with cleaned names, OR List of cleaned Strings

**Transformations:**
1. Symbol expansion: `%` → `percent`, `€` → `euro`, `$` → `dollar`, etc.
2. Diacritics removal: `café` → `cafe`
3. Lowercase
4. Non-alphanumeric → `_`, collapse runs
5. Prefix digits with `x_`: `1st` → `x_1st`
6. Empty → `col_N`
7. Collision resolution: `_2`, `_3`, etc.

**Examples:**
```t
clean_colnames(["Growth%", "MILLION€", "café"])
-- ["growth_percent", "million_euro", "cafe"]

clean_colnames(["A.1", "A-1"])
-- ["a_1", "a_1_2"]  (collision resolved)

df2 = clean_colnames(df)  -- DataFrame with cleaned column names
```

---

## Colcraft Package

Data manipulation verbs and window functions.

### Data Verbs

#### `select(dataframe, ...columns)`

Select columns by name. Supports dollar-prefix NSE syntax.

**Parameters:**
- `dataframe` — DataFrame
- `...columns` — Column references (`$name`)

**Returns:** DataFrame with selected columns

**Examples:**
```t
df |> select($name, $age)
df |> select($dept)
```

---

#### `filter(dataframe, predicate)`

Filter rows by condition. Supports NSE expressions with dollar-prefix column references.

**Parameters:**
- `dataframe` — DataFrame
- `predicate` — NSE expression (`$age > 25`)

**Returns:** DataFrame with matching rows

**Examples:**
```t
df |> filter($age > 30)
df |> filter($dept == "Engineering")
df |> filter($salary > 50000 and $active == true)
```

---

#### `mutate(dataframe, $col = expr)` / `mutate(dataframe, new_col, fn)`

Add or transform a column. Supports `$col = expr` named-arg syntax with NSE.

**Parameters (named-arg form):**
- `dataframe` — DataFrame
- `$col = expr` — Column name from `$col`, value from NSE expression

**Parameters (positional form):**
- `dataframe` — DataFrame
- `new_col` — Column reference (`$bonus`)
- `fn` — Function taking row dict: `\(row) ...`, OR
- `value` — Constant value for all rows

**Returns:** DataFrame with new/modified column

**Examples:**
```t
-- Named-arg NSE syntax
df |> mutate($bonus = $salary * 0.1)
df |> mutate($age_next_year = $age + 1)

-- Positional NSE with lambda
df |> mutate($bonus, \(row) row.salary * 0.1)

-- Grouped mutate (broadcast group result)
df |> group_by($dept) |> mutate($dept_size, \(g) nrow(g))
```

---

#### `arrange(dataframe, column, direction = "asc")`

Sort rows by column. Supports dollar-prefix NSE for column names.

**Parameters:**
- `dataframe` — DataFrame
- `column` — Column reference (`$age`)
- `direction` (optional) — "asc" or "desc" (default: "asc")

**Returns:** Sorted DataFrame

**Examples:**
```t
df |> arrange($age)
df |> arrange($salary, "desc")
```

---

#### `group_by(dataframe, ...columns)`

Group by one or more columns. Supports dollar-prefix NSE for column names.

**Parameters:**
- `dataframe` — DataFrame
- `...columns` — Column references (`$dept`)

**Returns:** Grouped DataFrame

**Usage:**
```t
-- Use with summarize to aggregate
df |> group_by($dept) |> summarize($avg_salary, \(g) mean(g.salary))

-- Use with mutate to broadcast group results
df |> group_by($dept) |> mutate($dept_count, \(g) nrow(g))
```

**Examples:**
```t
df |> group_by($dept)
df |> group_by($dept, $location)
```

---

#### `summarize(grouped_df, $col = expr)` / `summarize(grouped_df, new_col, fn)`

Aggregate grouped data. Supports `$col = expr` named-arg syntax with NSE.

**Parameters (named-arg form):**
- `grouped_df` — Grouped DataFrame (from `group_by()`)
- `$col = expr` — Column name from `$col`, aggregation from NSE expression (e.g. `sum($amount)`)

**Parameters (positional form):**
- `grouped_df` — Grouped DataFrame (from `group_by()`)
- `new_col` — Column reference (`$count`)
- `fn` — Aggregation function: `\(group) ...`

**Returns:** DataFrame with one row per group

**Examples:**
```t
-- Named-arg NSE syntax
df |> group_by($dept) |> summarize($count = nrow($dept))
df |> group_by($dept) |> summarize($avg_salary = mean($salary))
df |> group_by($region) |> summarize($total_sales = sum($sales), $n = nrow($region))

-- Positional NSE with lambda
df |> group_by($dept) |> summarize($count, \(g) nrow(g))
```

---

#### `ungroup(grouped_df)`

Remove grouping from a DataFrame.

**Parameters:**
- `grouped_df` — Grouped DataFrame

**Returns:** Ungrouped DataFrame

**Examples:**
```t
ungrouped = df |> group_by($dept) |> ungroup()
```

---

### Window Functions

Window functions compute values across rows without collapsing them.

#### Ranking Functions

##### `row_number(vector)`

Assign unique row numbers.

**Parameters:**
- `vector` — Vector or List

**Returns:** Vector of row numbers (1, 2, 3, ...), NA for NA positions

**Examples:**
```t
row_number([10, 30, 20])     -- Vector[1, 3, 2]
row_number([3, NA, 1])       -- Vector[2, NA, 1]
```

---

##### `min_rank(vector)`

Minimum rank (gaps after ties).

**Parameters:**
- `vector` — Vector or List

**Returns:** Vector of ranks

**Examples:**
```t
min_rank([1, 1, 2, 2, 2])    -- Vector[1, 1, 3, 3, 3]
min_rank([3, NA, 1, 3])      -- Vector[2, NA, 1, 2]
```

---

##### `dense_rank(vector)`

Dense rank (no gaps).

**Parameters:**
- `vector` — Vector or List

**Returns:** Vector of ranks

**Examples:**
```t
dense_rank([1, 1, 2, 2])     -- Vector[1, 1, 2, 2]
dense_rank([10, 10, 20])     -- Vector[1, 1, 2]
```

---

##### `cume_dist(vector)`

Cumulative distribution (proportion ≤ value).

**Parameters:**
- `vector` — Vector or List

**Returns:** Vector of Float (0.0 to 1.0)

**Examples:**
```t
cume_dist([1, 2, 3])         -- Vector[0.333..., 0.666..., 1.0]
```

---

##### `percent_rank(vector)`

Percent rank ((rank - 1) / (n - 1)).

**Parameters:**
- `vector` — Vector or List

**Returns:** Vector of Float (0.0 to 1.0)

**Examples:**
```t
percent_rank([1, 2, 3])      -- Vector[0.0, 0.5, 1.0]
```

---

##### `ntile(vector, n)`

Divide into n groups.

**Parameters:**
- `vector` — Vector or List
- `n` — Number of groups (Int)

**Returns:** Vector of group numbers (1 to n)

**Examples:**
```t
ntile([1, 2, 3, 4], 2)       -- Vector[1, 1, 2, 2]
ntile([1, 2, 3, 4, 5], 3)    -- Vector[1, 1, 2, 2, 3]
```

---

#### Offset Functions

##### `lag(vector, n = 1)`

Shift values forward (add NA at start).

**Parameters:**
- `vector` — Vector or List
- `n` (optional) — Number of positions (default: 1)

**Returns:** Vector with shifted values

**Examples:**
```t
lag([1, 2, 3, 4])            -- Vector[NA, 1, 2, 3]
lag([1, 2, 3, 4], 2)         -- Vector[NA, NA, 1, 2]
lag([1, NA, 3])              -- Vector[NA, 1, NA]
```

---

##### `lead(vector, n = 1)`

Shift values backward (add NA at end).

**Parameters:**
- `vector` — Vector or List
- `n` (optional) — Number of positions (default: 1)

**Returns:** Vector with shifted values

**Examples:**
```t
lead([1, 2, 3, 4])           -- Vector[2, 3, 4, NA]
lead([1, 2, 3, 4], 2)        -- Vector[3, 4, NA, NA]
```

---

#### Cumulative Functions

NA propagates: once NA is encountered, all subsequent values become NA.

##### `cumsum(vector)`

Cumulative sum.

**Examples:**
```t
cumsum([1, 2, 3, 4])         -- Vector[1, 3, 6, 10]
cumsum([1, NA, 3])           -- Vector[1, NA, NA]
```

---

##### `cummin(vector)`

Cumulative minimum.

**Examples:**
```t
cummin([3, 1, 4, 1])         -- Vector[3, 1, 1, 1]
```

---

##### `cummax(vector)`

Cumulative maximum.

**Examples:**
```t
cummax([1, 3, 2, 5])         -- Vector[1, 3, 3, 5]
```

---

##### `cummean(vector)`

Cumulative mean.

**Examples:**
```t
cummean([2, 4, 6])           -- Vector[2.0, 3.0, 4.0]
```

---

##### `cumall(vector)`

Cumulative AND (all true so far?).

**Examples:**
```t
cumall([true, true, false])  -- Vector[true, true, false]
```

---

##### `cumany(vector)`

Cumulative OR (any true so far?).

**Examples:**
```t
cumany([false, true, false]) -- Vector[false, true, true]
```

---

## Pipeline Package

Pipeline introspection and management.

### `pipeline_nodes(pipeline)`

Get all node names in a pipeline.

**Parameters:**
- `pipeline` — Pipeline object

**Returns:** List of Strings (node names)

**Examples:**
```t
p = pipeline { x = 1; y = 2; z = x + y }
pipeline_nodes(p)  -- ["x", "y", "z"]
```

---

### `pipeline_deps(pipeline, node_name)`

Get dependencies of a specific node.

**Parameters:**
- `pipeline` — Pipeline object
- `node_name` — Name of the node (String)

**Returns:** List of Strings (dependency names)

**Examples:**
```t
p = pipeline { x = 1; y = 2; z = x + y }
pipeline_deps(p, "z")  -- ["x", "y"]
pipeline_deps(p, "x")  -- []
```

---

### `pipeline_node(pipeline, node_name)`

Get the value of a specific node.

**Parameters:**
- `pipeline` — Pipeline object
- `node_name` — Name of the node (String)

**Returns:** Node value

**Examples:**
```t
p = pipeline { x = 10; doubled = x * 2 }
pipeline_node(p, "x")       -- 10
pipeline_node(p, "doubled") -- 20
```

---

### `pipeline_run(pipeline)`

Re-execute a pipeline.

**Parameters:**
- `pipeline` — Pipeline object

**Returns:** Pipeline object with updated values

**Examples:**
```t
p = pipeline { x = 10; y = x * 2 }
p2 = pipeline_run(p)
```

---

## Explain Package

Introspection and LLM tooling.

### `explain(value)`

Get detailed explanation of a value. For DataFrames, returns a compact summary by default showing `kind`, `nrow`, `ncol`, and a `hint`. Detailed fields (`schema`, `na_stats`, `example_rows`) are accessible via dot notation.

**Parameters:**
- `value` — Any value

**Returns:** Dict with introspection data

**Examples:**
```t
explain(42)
-- {`kind`: "value", `type`: "Int", `value`: 42}

explain(df)
-- {`kind`: "dataframe", `nrow`: 100, `ncol`: 5, `hint`: "Use explain(df).schema, ..."}

-- Access detailed fields:
explain(df).schema        -- list of column name/type pairs
explain(df).na_stats      -- NA count per column
explain(df).example_rows  -- first 5 rows as list of dicts
```

---

### `explain_json(value)`

Export value metadata as JSON (for LLM consumption).

**Parameters:**
- `value` — Any value

**Returns:** JSON String

**Examples:**
```t
explain_json(df)
-- {"type": "DataFrame", "rows": 100, "columns": ["name", "age", ...]}
```

---

### `intent_fields(intent)`

Get all fields from an intent block.

**Parameters:**
- `intent` — Intent object

**Returns:** Dict of field names to values

**Examples:**
```t
i = intent { description: "Analysis", assumes: "Clean data" }
intent_fields(i)
-- {description: "Analysis", assumes: "Clean data"}
```

---

### `intent_get(intent, field)`

Get a specific field from an intent block.

**Parameters:**
- `intent` — Intent object
- `field` — Field name (String)

**Returns:** Field value

**Examples:**
```t
i = intent { description: "Customer analysis" }
intent_get(i, "description")  -- "Customer analysis"
```

---

## Operators

### Arithmetic

| Operator | Description | Example |
|----------|-------------|---------|
| `+` | Addition / String concatenation | `2 + 3` → `5`, `"a" + "b"` → `"ab"` |
| `-` | Subtraction | `5 - 2` → `3` |
| `*` | Multiplication | `4 * 5` → `20` |
| `/` | Division | `15 / 3` → `5` |
| `%` | Modulo | `7 % 3` → `1` |

### Comparison

| Operator | Description | Example |
|----------|-------------|---------|
| `==` | Equal | `5 == 5` → `true` |
| `!=` | Not equal | `5 != 3` → `true` |
| `<` | Less than | `3 < 5` → `true` |
| `>` | Greater than | `5 > 3` → `true` |
| `<=` | Less or equal | `5 <= 5` → `true` |
| `>=` | Greater or equal | `3 >= 2` → `true` |

### Logical (Scalar Control Flow)

| Operator | Description | Example |
|----------|-------------|---------|
| `&&` | Logical AND (Short-circuit) | `true && false` → `false` |
| `||` | Logical OR (Short-circuit) | `true || false` → `true` |
| `!` | Logical NOT (Strict) | `!false` → `true` |

### Bitwise / Boolean (Strict)

| Operator | Description | Example |
|----------|-------------|---------|
| `&` | Bitwise/Boolean AND | `true & false` → `false`, `3 & 1` → `1` |
| `|` | Bitwise/Boolean OR | `true | false` → `true`, `3 | 1` → `3` |

### Membership

| Operator | Description | Logic |
| :--- | :--- | :--- |
| `in` | Check if element exists in list | `x in [a, b]` |

**Examples**:
```t
1 in [1, 2, 3]       -- true
4 in [1, 2, 3]       -- false
[1, 4] in [1, 2, 3]  -- [true, false] (Broadcasting)
```

### Broadcasting

Standard operators can be broadcasted over lists/vectors by prefixing with `.`.

| Operator | Description | Logic |
| :--- | :--- | :--- |
| `.+`, `.-`, `.*`, `./` | Element-wise Arithmetic | `[1, 2] .+ 1` -> `[2, 3]` |
| `.==`, `.!=`, `.<`, `.>`, `.<=`, `.>=` | Element-wise Comparison | `[1, 2] .> 1` -> `[false, true]` |
| `.&`, `.|` | Element-wise Logical/Bitwise | `[true, false] .& true` -> `[true, false]` |

> [!NOTE]
> `in` automatically broadcasts if the left-hand side is a list/vector. You do not need `.in`.


### Pipes

| Operator | Description | Error Handling |
|----------|-------------|----------------|
| `\|>` | Conditional pipe | Short-circuits on error |
| `?\|>` | Maybe-pipe | Forwards errors to function |

---

## Type System

| Type | Example | Description |
|------|---------|-------------|
| `Int` | `42` | Integer numbers |
| `Float` | `3.14` | Floating-point numbers |
| `Bool` | `true`, `false` | Boolean values |
| `String` | `"hello"` | Text strings |
| `List` | `[1, 2, 3]` | Ordered collections |
| `Dict` | `{x: 1, y: 2}` | Key-value maps |
| `Vector` | Column data | Typed arrays (from DataFrames) |
| `DataFrame` | Table data | First-class tabular data |
| `Function` | `\(x) x + 1` | First-class functions |
| `NA` | `NA`, `na_int()` | Explicit missing values (typed) |
| `Error` | `error("msg")` | Structured errors (not exceptions) |
| `Null` | `null` | Absence of value |
| `Intent` | `intent { ... }` | LLM metadata block |
| `Pipeline` | `pipeline { ... }` | DAG computation graph |
| `Formula` | `y ~ x` | Statistical model specification |

---

**Need more examples?** Check the [Data Manipulation Examples](data_manipulation_examples.md) and [Pipeline Tutorial](pipeline_tutorial.md).
