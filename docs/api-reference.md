# API Reference

Package-oriented guide to T's standard library.

> **Coverage**: Package overview and worked examples  
> **Exhaustive per-function reference**: [`docs/reference/index.md`](reference/index.md), generated from source docstrings  
> **Auto-loaded**: All standard packages are automatically available in every T session

---

## Table of Contents

- [Shell Interaction](#shell-interaction) — Executing commands from T
- [Core Package](#core-package) — Basic functional utilities
- [Base Package](#base-package) — Errors, NA, assertions
- [Math Package](#math-package) — Mathematical functions
- [Stats Package](#stats-package) — Statistical functions
- [DataFrame Package](#dataframe-package) — CSV I/O and DataFrame operations
- [Colcraft Package](#colcraft-package) — Data manipulation verbs and window functions
- [Chrono Package](#chrono-package) — High-performance date and time manipulation
- [Strcraft Package](#strcraft-package) — Modern string manipulation
- [Pipeline Package](#pipeline-package) — Pipeline introspection
- [Explain Package](#explain-package) — Introspection and debugging tools

---

For generated one-page documentation for every exported function, including newer Chrono, string, join, factor, and helper APIs, use the [Function Reference](reference/index.md).

---

## Core Syntax: Lists, Dictionaries, and Blocks

These forms are **distinct and non-overlapping**:

- `[a, b, c]` → List literal
- `[key: value, ...]` → Dictionary literal
- `{ ... }` → Block statement (control-flow/body syntax), **not** a dictionary

### Bracket literal rule (`[...]`)

When parsing a bracket literal, T applies this rule:

1. Parse comma-separated top-level items.
2. If **any** top-level item is `key: value`, the whole literal is treated as a dictionary.
3. Otherwise, it is treated as a list.

This means:

```t
[]                    -- empty List
[:]                   -- empty Dict
[1, 2, 3]             -- List
[name: "alice"]      -- Dict
[name: "alice", age: 32]  -- Dict
```

### Disallowed mixed forms

A single bracket literal cannot mix dictionary entries and plain expressions:

```t
[name: "alice", 12]  -- Parse error
[name:]               -- Parse error
```

### Braces are blocks

`{ ... }` is reserved for block syntax (e.g., in control flow and pipeline/intent constructs).
It is not used for general dictionary literals.

An empty brace block `{}` parses as an empty block (`Block []`) and evaluates to `NA` at runtime.
Braces are never used for dictionary literals; dictionaries always use the bracket (`[...]`) syntax described above.

---

## Shell Interaction

### Shell Escape (`?<{ ... }>`)

T provides first-class support for executing shell commands using the `?<{ }>` syntax.

- **As a Statement**: Prints output directly to `stdout`.
- **As an Expression**: Captures `stdout` as a `String`.
- **Error Handling**: Non-zero exit codes produce a `ShellError` containing `stderr`.
- **Working Directory**: The `cd` command is special-cased to change the interpreter's working directory.

**Examples:**
```t
?<{ls -la}>             -- Prints directory listing
files = ?<{ls}>         -- Captures filenames in a string
?<{cd /tmp}>            -- Changes working directory to /tmp
```


---

## Core Package

Fundamental functional programming utilities.

### `print(value)`

Print a value to standard output.

**Parameters:**


- `value` — Any value to print

**Returns:**

The printed value (for chaining)

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

**Returns:**

The value (for chaining)

**Examples:**
```t
pretty_print(df)  -- Formatted DataFrame output
```

---

### `type(value)`

Get the type name of a value as a string.

**Parameters:**


- `value` — Any value

**Returns:**

`String` — Type name

**Examples:**
```t
type(42)             -- "Int"
type(3.14)           -- "Float"
type(true)           -- "Bool"
type("hello")        -- "String"
type([1, 2])         -- "List"
type([x: 1])         -- "Dict"
type(NA)             -- "NA"
type(error("x"))     -- "Error"
type(df)             -- "DataFrame"
```

---

### `to_integer(value)`

Convert a value to an integer robustly. Handles strings with spaces, percentages, commas, and recognizes 'TRUE'/'FALSE'. Also propagates vectorization over Collections.

**Parameters:**


- `value` — Any value (String, Bool, Float, List, Vector)

**Returns:**

`Int`, `NA`, or a Collection of `Int`/`NA`

**Examples:**
```t
to_integer("12 300")     -- 12300
to_integer("TRUE")       -- 1
to_integer("FALSE")      -- 0
to_integer("15%")        -- 15
to_integer("3,14")       -- 3
to_integer(3.14)         -- 3
to_integer("hello")      -- NA(Int)
to_integer(["1", "2"])   -- [1, 2]
```

---

### `to_float(value)` / `to_numeric(value)`

Convert a value to a float robustly. `to_numeric` is an alias for `to_float`. Handles strings with spaces, percentages, commas, and recognizes 'TRUE'/'FALSE'. Also propagates vectorization over Collections.

**Parameters:**


- `value` — Any value (String, Bool, Int, List, Vector)

**Returns:**

`Float`, `NA`, or a Collection of `Float`/`NA`

**Examples:**
```t
to_float("3,14")         -- 3.14
to_float("15%")          -- 15.0
to_float(" 1 200.5 ")    -- 1200.5
to_numeric("TRUE")       -- 1.0
to_numeric("F")          -- 0.0
to_float(42)             -- 42.0
to_float("hello")        -- NA(Float)
to_numeric(["1", "2"])   -- [1.0, 2.0]
```

---

### `length(collection)`

Get the number of elements in a collection.

**Parameters:**


- `collection` — List, Vector, or String

**Returns:**

`Int` — Number of elements

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

**Returns:**

Single element (for Lists) or DataFrame (for DataFrames)

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

**Returns:**

List (for Lists) or DataFrame (for DataFrames)

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

**Returns:**

List (or Vector) of results

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

**Returns:**

List (or Vector) of matching elements

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

**Returns:**

`Int` or `Float` — Sum

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

**Returns:**

List of numbers

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

**Returns:**

`Bool` — true if value is an Error

**Examples:**
```t
is_error(42)             -- false
is_error(error("msg"))   -- true
is_error(1 / 0)          -- true
```

---

### `getwd()`

Returns the current working directory of the T interpreter.

**Returns:**

`String` — Working directory path

---

### `file_exists(path)`

Check if a regular file exists at the given path. Returns `false` for directories.

**Parameters:**


- `path` — File path (String or Symbol)

**Returns:**

`Bool`

---

### `dir_exists(path)`

Check if a directory exists at the given path.

**Parameters:**


- `path` — Directory path (String or Symbol)

**Returns:**

`Bool`

---

### `read_file(path)`

Read the entire contents of a file as a string.

**Parameters:**


- `path` — File path (String or Symbol)

**Returns:**

`String` or `Error(FileError)`

---

### `list_files(path, pattern)`

List files and directories in a given path.

**Parameters:**


- `path` (optional) — Directory to list (default: ".")
- `pattern` (optional) — Regex pattern to filter filenames

**Returns:**

`List[String]` or `Error(FileError)`

---

### `env(name)`

Get the value of an environment variable.

**Parameters:**


- `name` — Environment variable name (String or Symbol)

**Returns:**

`String` or `NA` if not found

---

### `exit(code)`

Exits the T interpreter.

**Parameters:**


- `code` (optional) — Exit code integer (default: 0)

---

### `path_join(...)`

Join multiple path segments using the system-specific separator.

**Parameters:**


- `...` — One or more path segments (String or Symbol)

**Returns:**

`String`

---

### `path_basename(path)`

Get the filename/last component of a path.

**Parameters:**


- `path` — Path string

**Returns:**

`String`

---

### `path_dirname(path)`

Get the directory portion of a path.

**Parameters:**


- `path` — Path string

**Returns:**

`String`

---

### `path_ext(path)`

Get the file extension (including the dot). Returns `NA` if no extension is found.

**Parameters:**


- `path` — Path string

**Returns:**

`String` or `NA`

---

### `path_stem(path)`

Get the filename without its extension.

**Parameters:**


- `path` — Path string

**Returns:**

`String`

---

### `path_abs(path)`

Resolves a relative path to an absolute path against the current working directory.

**Parameters:**


- `path` — Path string

**Returns:**

`String`


---

### `rm(...)`

Remove one or more variables from the environment by name. Supports bare symbols (R-style selective removal), strings, and lists of names via the `list` parameter.

**Parameters:**

- `...` — One or more variable symbols or strings identifying variables to remove.
- `list` (optional) — A List of strings or symbols to remove.

**Returns:**

`NA`

**Examples:**

```t
x = 10; y = 20
rm(x, y)          -- Removes x and y

z = 30
rm("z")           -- Removes z

vars = ["a", "b"]
rm(list = vars)   -- Removes variables 'a' and 'b'
```


---

## Base Package

Error handling, NA values, and assertions.

### `error(message)` / `error(code, message)`

Create an error value.

**Parameters:**


- `message` — Error message string
- `code` (optional) — Error code string

**Returns:**

`Error` value

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

**Returns:**

`String` — Error code

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

**Returns:**

`String` — Error message

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

**Returns:**

`String` — Context information

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

**Returns:**

`true` if condition holds

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

**Returns:**

Typed NA value

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

**Returns:**

`Bool` — true if value is NA

**Examples:**
```t
is_na(NA)           -- true
is_na(na_int())     -- true
is_na(42)           -- false
is_na("hello")      -- false
```

---

## Math Package

Mathematical functions operating on scalars and vectors.

### `sqrt(x)`

Square root.

**Parameters:**


- `x` — Number (Int or Float)

**Returns:**

`Float`

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

**Returns:**

Same type as input

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

**Returns:**

`Float`

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

**Returns:**

`Float`

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

**Returns:**

`Float`

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

**Returns:**

Minimum value

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

**Returns:**

Maximum value

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

**Returns:**

`Float` — Mean value

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

**Returns:**

`Float` — Standard deviation

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

**Returns:**

`Float` — Quantile value

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

**Returns:**

`Float` — Correlation (-1.0 to 1.0)

**Examples:**
```t
cor([1, 2, 3], [2, 4, 6])                  -- 1.0 (perfect positive)
cor([1, 2, 3], [3, 2, 1])                  -- -1.0 (perfect negative)
cor([1, 2, 3], [4, 5, 6])                  -- 1.0
cor([1, NA, 3], [2, 4, NA], na_rm = true)  -- 1.0 (uses [1,3] and [2,4])
```

---

### `lm(data, formula)`

Fit a linear regression model (ordinary least squares).

**Parameters:**


- `data` — DataFrame
- `formula` — Formula object (`y ~ x1 + x2`)

**Returns:**

Model object. Use `summary()` and `fit_stats()` to inspect. PMML imports accept T's extended fields (e.g. `std_error`, `statistic`, `p_value`) and are not schema-validated.

**Examples:**
```t
model = lm(data = df, formula = mpg ~ wt + hp)
print(model)
```

---

### `summary(model)`

Get a tidy DataFrame of model coefficients. Similar to `broom::tidy()` in R.

**Parameters:**


- `model` — Linear model object (from `lm()` or imported via PMML)

**Returns:**

DataFrame with columns: `term`, `estimate`, `std_error`, `statistic`, `p_value`.

**Examples:**
```t
summary(model)
```

---

### `fit_stats(model)`

Get a single-row DataFrame of model-level statistics. Similar to `broom::glance()` in R.

**Parameters:**


- `model` — Model object (linear model, decision tree, or random forest; PMML imports supported)

**Returns:**

DataFrame with statistics like `r_squared`, `AIC`, `BIC`, `sigma`, etc.

**Examples:**
```t
fit_stats(model)
```

---

### `add_diagnostics(model, data)`

Augment data with per-observation diagnostics. Similar to `broom::augment()` in R.

**Parameters:**


- `model` — Linear model object
- `data` — Original DataFrame used for fitting

**Returns:**

DataFrame with original columns plus diagnostics (`.fitted`, `.resid`, etc.).

**Examples:**
```t
add_diagnostics(model, data = df)
```

---

### `predict(data, model)`

Perform vectorized prediction on a new DataFrame. Supports linear models as well as PMML decision trees and random forests.

**Parameters:**


- `data` — DataFrame containing predictor columns
- `model` — Linear model object

**Returns:**

Vector of predicted values.

**Examples:**
```t
preds = predict(new_df, model)
```

---

## DataFrame Package

CSV I/O and DataFrame introspection.

### `read_csv(path, separator = ",", skip_lines = 0, skip_header = false, clean_colnames = false)`

Read a CSV file into a DataFrame.

**Current implementation note:**

`read_csv()` currently parses CSV in OCaml and then constructs an Arrow-backed `DataFrame`. The repository also contains a lower-level native Arrow CSV reader, but that backend path is not yet the public default entry point.

**Parameters:**


- `path` — File path (String)
- `separator` (optional) — Column separator (default: ",")
- `skip_lines` (optional) — Number of lines to skip at start (default: 0)
- `skip_header` (optional) — If true, treat first row as data (default: false)
- `clean_colnames` (optional) — If true, normalize column names (default: false)

**Returns:**

`DataFrame`

**Examples:**
```t
df = read_csv("data.csv")
df = read_csv("data.tsv", separator = "\t")
df = read_csv("data.csv", skip_lines = 2)
df = read_csv("messy.csv", clean_colnames = true)
```

---

### `read_arrow(path)`

Read an Arrow IPC file into a DataFrame.

**Parameters:**

- `path` — Input file path (String)

**Returns:**

`DataFrame`

**Examples:**
```t
df = read_arrow("data.arrow")
```

---

### `write_arrow(dataframe, path)`

Write a DataFrame to an Arrow IPC file.

**Parameters:**

- `dataframe` — DataFrame to write
- `path` — Output file path (String)

**Returns:**

`NA`

**Examples:**
```t
write_arrow(df, "snapshot.arrow")
```

---

### `write_csv(dataframe, path, separator = ",")`

Write a DataFrame to a CSV file.

**Parameters:**


- `dataframe` — DataFrame to write
- `path` — Output file path (String)
- `separator` (optional) — Column separator (default: ",")

**Returns:**

`NA`

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

**Returns:**

`Int` — Row count

**Examples:**
```t
nrow(df)  -- 100
```

---

### `ncol(dataframe)`

Get number of columns.

**Parameters:**


- `dataframe` — DataFrame

**Returns:**

`Int` — Column count

**Examples:**
```t
ncol(df)  -- 5
```

---

### `colnames(dataframe)`

Get column names.

**Parameters:**


- `dataframe` — DataFrame

**Returns:**

List of Strings

**Examples:**
```t
colnames(df)  -- ["name", "age", "dept", "salary"]
```

---

### `glimpse(dataframe)`

Get a compact overview of a DataFrame, showing column names, types, and example values. Similar to dplyr's `glimpse()`.

**Parameters:**


- `dataframe` — DataFrame

**Returns:**

Dict with `kind`, `nrow`, `ncol`, and `columns` (list of column summaries)

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

**Returns:**

DataFrame with cleaned names, OR List of cleaned Strings

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

**Returns:**

DataFrame with selected columns

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

**Returns:**

DataFrame with matching rows

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

**Returns:**

DataFrame with new/modified column

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

**Returns:**

Sorted DataFrame

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

**Returns:**

Grouped DataFrame

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

**Returns:**

DataFrame with one row per group

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

**Returns:**

Ungrouped DataFrame

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

**Returns:**

Vector of row numbers (1, 2, 3, ...), NA for NA positions

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

**Returns:**

Vector of ranks

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

**Returns:**

Vector of ranks

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

**Returns:**

Vector of Float (0.0 to 1.0)

**Examples:**
```t
cume_dist([1, 2, 3])         -- Vector[0.333..., 0.666..., 1.0]
```

---

##### `percent_rank(vector)`

Percent rank ((rank - 1) / (n - 1)).

**Parameters:**


- `vector` — Vector or List

**Returns:**

Vector of Float (0.0 to 1.0)

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

**Returns:**

Vector of group numbers (1 to n)

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

**Returns:**

Vector with shifted values

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

**Returns:**

Vector with shifted values

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

## Chrono Package

High-performance date and time manipulation, inspired by R's `lubridate`.

### `as_date(value)` / `as_datetime(value)`

Convert values to Date or Datetime types.

**Parameters:**

- `value` — String, Number, or Collection of values

**Returns:**

`Date` / `Datetime` / `Collection`

**Examples:**
```t
as_date("2023-05-15")  -- 2023-05-15
as_datetime("2023-05-15 14:00:00")
```

---

### `ymd(string)` / `dmy(string)`

Parse strings into dates using common formats.

**Parameters:**

- `string` — Date string

**Returns:**

`Date`

**Examples:**
```t
ymd("2023-05-15")
dmy("15/05/2023")
```

---

### `floor_date(datetime, unit)`

Round a date/datetime down to the nearest unit (year, month, day, hour, etc.).

**Parameters:**

- `datetime` — Date or Datetime
- `unit` — Unit as string ("month", "day", etc.)

**Returns:**

Same as input type

**Examples:**
```t
floor_date(as_date("2023-05-15"), "month")  -- 2023-05-01
```

---

## Strcraft Package

Modern string manipulation utilities, inspired by R's `stringr`.

### `str_replace(string, pattern, replacement)`

Replace the first occurrence of a pattern with a replacement string. Use `str_replace_all` for all occurrences.

**Parameters:**

- `string` — Input string
- `pattern` — Regex pattern
- `replacement` — Replacement string

**Returns:**

`String`

**Examples:**
```t
str_replace("hello world", "world", "T")  -- "hello T"
```

---

### `str_detect(string, pattern)`

Check if a pattern exists in a string.

**Parameters:**

- `string` — Input string
- `pattern` — Regex pattern

**Returns:**

`Bool`

**Examples:**
```t
str_detect("apple", "p")  -- true
```

---

### `str_glue(...)`

Interpolate variables and expressions into strings. Similar to Python f-strings.

**Parameters:**

- `...` — String with `{expression}` placeholders

**Returns:**

`String`

**Examples:**
```t
name = "Alice"
str_glue("Hello {name}")  -- "Hello Alice"
```

---

## Pipeline Package

Pipeline introspection and management.

### `node(command, script = NA, runtime = "T", serializer = "default", deserializer = "default", env_vars = [:], args = [:], shell = NA, shell_args = [], functions = [], include = [], noop = false)`

Configure execution settings such as the runtime and custom serialized methods for a pipeline node.

**Parameters:**


- `command` — The expression to evaluate (positional or named).
- `runtime` (optional) — The runtime environment (`T`, `R`, `Python`, `sh`, `Quarto`). Default: `T`.
- `serializer` (optional) — Write artifact overriding mechanism.
- `deserializer` (optional) — Read artifact overriding mechanism.
- `env_vars` (optional) — Dictionary of environment variables to pass into the Nix sandbox.
- `args` (optional) — Runtime/tool arguments. Lists become positional CLI arguments for `runtime = sh`.
- `shell` (optional) — Shell interpreter for `runtime = sh`. Default: `sh`.
- `shell_args` (optional) — Additional arguments passed to the shell interpreter.
- `functions` (optional) — Code files to source before execution.
- `include` (optional) — Additional files to bring into the sandbox.
- `noop` (optional) — Whether to skip execution and generate a stub.

**Returns:**

The evaluated return value of the node `command`.

**Examples:**
```t
p = pipeline {
y = node(command = x + 5, runtime = T)
z = node(
command = build_model(y),
runtime = R,
functions = ["utils.R"],
include = "config.yml"
)
}
```

---

### `py(command, script = NA, serializer = "default", deserializer = "default", env_vars = [:], functions = [], include = [], noop = false)`

### `pyn(command, script = NA, serializer = "default", deserializer = "default", env_vars = [:], functions = [], include = [], noop = false)`

Configure a Python Pipeline Node. A convenience wrapper around `node()` with `runtime = "Python"`. Used directly within a `pipeline { ... }` block to execute Python code.

**Parameters:**


- `command` — The expression to evaluate inside the Python node (must be enclosed in `<{ ... }>` blocks).
- `serializer` (optional) — Custom serializer function. Default: `default`.
- `deserializer` (optional) — Custom deserializer function. Default: `default`.
- `env_vars` (optional) — Dictionary of environment variables to pass into the Nix sandbox.
- `functions` (optional) — Python files to source before execution.
- `include` (optional) — Additional files for the sandbox.
- `noop` (optional) — Whether to skip execution and generate a stub. Default: `false`.

**Returns:**

The evaluated return value of the command.

---

### `rn(command, script = NA, serializer = "default", deserializer = "default", env_vars = [:], functions = [], include = [], noop = false)`

Configure an R Pipeline Node. A convenience wrapper around `node()` with `runtime = "R"`. Used directly within a `pipeline { ... }` block to execute R code.

**Parameters:**


- `command` — The expression to evaluate inside the R node (must be enclosed in `<{ ... }>` blocks).
- `serializer` (optional) — Custom serializer function. Default: `default`.
- `deserializer` (optional) — Custom deserializer function. Default: `default`.
- `env_vars` (optional) — Dictionary of environment variables to pass into the Nix sandbox.
- `functions` (optional) — R scripts to source before execution.
- `include` (optional) — Additional files for the sandbox.
- `noop` (optional) — Whether to skip execution and generate a stub. Default: `false`.

**Returns:**

The evaluated return value of the command.

---

### `shn(command, script = NA, serializer = "text", deserializer = "default", env_vars = [:], args = [], shell = "sh", shell_args = [], functions = [], include = [], noop = false)`

Configure a shell pipeline node. A convenience wrapper around `node()` with `runtime = "sh"`. Use it for CLI tools, inline shell scripts, and `.sh` files inside `pipeline { ... }` blocks.

**Parameters:**

- `command` — The shell command or raw shell script body to execute.
- `script` (optional) — Path to an external `.sh` file. Mutually exclusive with `command`.
- `serializer` (optional) — Custom serializer function. Default: `text`.
- `deserializer` (optional) — Custom deserializer function. Default: `default`.
- `env_vars` (optional) — Dictionary of environment variables to pass into the Nix sandbox.
- `args` (optional) — Runtime arguments. Lists become positional CLI arguments for exec-style shell nodes.
- `shell` (optional) — Shell interpreter. Default: `sh`; use `bash` when you need Bash-specific parsing.
- `shell_args` (optional) — Additional arguments for the shell interpreter, such as `["-lc"]`.
- `functions` (optional) — Additional files to include in the sandbox before execution.
- `include` (optional) — Additional files for the sandbox.
- `noop` (optional) — Whether to skip execution and generate a stub. Default: `false`.

**Returns:**

The evaluated return value of the command.

---

### `pipeline_nodes(pipeline)`

Get all node names in a pipeline.

**Parameters:**


- `pipeline` — Pipeline object

**Returns:**

List of Strings (node names)

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

**Returns:**

List of Strings (dependency names)

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

**Returns:**

Node value

**Examples:**
```t
p = pipeline { x = 10; doubled = x * 2 }
pipeline_node(p, "x")       -- 10
pipeline_node(p, "doubled") -- 20
```

---

### `pipeline_run(pipeline)`

Re-execute a pipeline in-memory.

**Parameters:**


- `pipeline` — Pipeline object

**Returns:**

Pipeline object with updated values

**Examples:**
```t
p = pipeline { x = 10; y = x * 2 }
p2 = pipeline_run(p)
```

---

### `populate_pipeline(pipeline, build = false)`

Prepare pipeline infrastructure in `_pipeline/`.

**Parameters:**


- `pipeline` — Pipeline object
- `build` (optional) — If true, triggers a Nix build of all nodes.

**Returns:**

Success message or Error.

**Examples:**
```t
populate_pipeline(p)
populate_pipeline(p, build = true)
```

---

### `build_pipeline(pipeline)`

Shorthand for `populate_pipeline(p, build = true)`. Recommended for scripts run with `t run`.

**Parameters:**


- `pipeline` — Pipeline object

---

### `read_node(name, which_log = NA)`

Read a materialized artifact from a previous build.

**Parameters:**


- `name` — Name of the node to read (String)
- `which_log` (optional) — Regex pattern or filename of a specific build log. Defaults to latest.

**Returns:**

Deserialized value.

**Examples:**
```t
read_node("summary_stats")
read_node("model_v1", which_log = "20260221")
```

---

### `inspect_pipeline(which_log = NA)`

View build status and output paths for a pipeline build.

**Parameters:**


- `which_log` (optional) — Specific build log to inspect.

**Returns:**

DataFrame with columns: `node`, `success`, `path`, `output`.

---

### `list_logs()`

List all available build logs in `_pipeline/`.

**Returns:**

DataFrame with columns: `filename`, `mod_time`, `size_kb`.

---

## Explain Package

Introspection and LLM tooling.

### `explain(value)`

Get detailed explanation of a value. For DataFrames, returns a compact summary by default showing `kind`, `nrow`, `ncol`, and a `hint`. Detailed fields (`schema`, `na_stats`, `example_rows`) are accessible via dot notation.

**Parameters:**


- `value` — Any value

**Returns:**

Dict with introspection data

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

**Returns:**

JSON String

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

**Returns:**

Dict of field names to values

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

**Returns:**

Field value

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
| `Dict` | `[x: 1, y: 2]` | Key-value maps |
| `Vector` | Column data | Typed arrays (from DataFrames) |
| `DataFrame` | Table data | First-class tabular data |
| `Function` | `\(x) x + 1` | First-class functions |
| `NA` | `NA`, `na_int()` | Explicit missing values (typed) |
| `Error` | `error("msg")` | Structured errors (not exceptions) |
| `Intent` | `intent { ... }` | LLM metadata block |
| `Pipeline` | `pipeline { ... }` | DAG computation graph |
| `Formula` | `y ~ x` | Statistical model specification |

---

## Next Steps

Now that you've explored the API, learn how to build reproducible data pipelines:

1. **[Pipeline Tutorial](pipeline_tutorial.md)** — Master T's core execution model.
2. **[Data Manipulation Examples](data_manipulation_examples.md)** — Practical examples of data wrangling.
3. **[Project Development](project_development.md)** — Master T's project structure and dependency management.
4. **[Package Development](package_development.md)** — Create reusable T libraries.
