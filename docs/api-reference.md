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
- [Lens Package](#lens-package) — Composable access and update lenses
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

### `sym(value)`

Convert a string name into a `Symbol` so it can be injected into quoted code with `!!`. Existing symbols pass through unchanged.

**Parameters:**


- `value` — String or Symbol

**Returns:**

`Symbol`

**Examples:**
```t
sym("mpg")                           -- mpg
expr(select(df, !!sym("mpg")))       -- expr(select(df, mpg))
name = "result"
expr(f(!!sym(name) := 42))           -- expr(f(result = 42))
```

---

### `args(fn)`

Returns a dictionary of parameter names and their expected types for a function.

---

### `is_error(value)`

Returns `true` if the value is an Error object.

---

### `get(target, selector = NA, default = NA)`

Unified retrieval for variables, collection elements, pipeline nodes, or lens focuses.

**Examples:**
```t
get("salary")                -- variable lookup
get(list, 0)                  -- indexing
get(df, col_lens("mpg"))      -- lens focus
get(val, 0)                   -- fallback if val is NA/Error
```

---

### `ifelse(condition, true_val, false_val, missing = NA, out_type = NA)`

Vectorized conditional selection.

---

### `casewhen(...formulas, .default = NA)`

Vectorized multi-condition switch. Uses `condition ~ value` formulas.

---

### `identical(a, b)`

Deep equality check. Works for collections and complex objects.

---

### `eval(expr)` / `expr(x)` / `exprs(...)`
### `quo(x)` / `quos(...)` / `enquo(p)` / `enquos(...)`

Metaprogramming and quotation utilities.

---

### `body(fn)` / `source(fn)`

Inspect function implementation.

---

### `run(cmd)`

Execute a shell command and return its stdout as a string.

---

### `cat(...values, sep = " ", file = NA, append = false)`

Print values to stdout or a file without a trailing newline (unless specified).

---

### `getwd()` / `exit(code = 0)`

Environment and process control.

---

### `file_exists(path)` / `dir_exists(path)` / `list_files(path, pattern = NA)`
### `read_file(path)` / `read_lines(path)`

File system introspection and reading.

---

### `path_join(...)` / `path_abs(path)`
### `path_basename(path)` / `path_dirname(path)`
### `path_ext(path)` / `path_stem(path)`

Cross-platform path manipulation.

---

### `show_plot(plot)`

Display a plot object (depends on the environment's plot viewer).

---

### `env()`

Returns a list of all variable names currently in the environment.

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


- `message_or_code` — Error message (if 1 arg) or error code (if 2 args)
- `message` (optional) — Error message (if 2 args)

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

`Dict` — A dictionary of related context data.

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

### `serialize(value, path)`

Serializes a value to a `.tobj` file.

**Parameters:**

- `value` — Any value to serialize
- `path` — Output file path (String)

**Returns:**

`NA`

**Seealso:** `deserialize`

---

### `deserialize(path)`

Deserializes a value from a `.tobj` file.

**Parameters:**

- `path` — Input file path (String)

**Returns:**

`Any` — The deserialized value

**Seealso:** `serialize`

---

### `t_write_json(value, path)`

Serializes a T value to a JSON file. This is used as the universal baseline for object transport between runtimes.

**Parameters:**

- `value` — Any value to serialize
- `path` — Path to the destination file (String)

**Returns:**

`NA`

---

### `t_read_json(path)`

Deserializes a T value from a JSON file. Automatically handles type conversion for scalars, lists, and dictionaries.

**Parameters:**

- `path` — Path to the JSON file (String)

**Returns:**

`Any` — The deserialized value

---

## Math Package

Mathematical functions operating on scalars and vectors. Most functions are vectorized over Collections.

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

### `log(x)` / `log10(x)` / `log2(x)`

Logarithm functions. `log` is natural logarithm (base e).

**Parameters:**

- `x` — Number (must be positive)

**Returns:**

`Float`

**Examples:**
```t
log(10)      -- 2.30258509299
log10(100)   -- 2.0
log2(1024)   -- 10.0
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
pow(2, 10)   -- 1024.0
pow(9, 0.5)  -- 3.0
```

---

### `sin(x)` / `cos(x)` / `tan(x)`

Standard trigonometric functions (input in radians).

---

### `asin(x)` / `acos(x)` / `atan(x)` / `atan2(y, x)`

Inverse trigonometric functions. `atan2` returns the angle whose tangent is y/x.

---

### `sinh(x)` / `cosh(x)` / `tanh(x)`
### `asinh(x)` / `acosh(x)` / `atanh(x)`

Hyperbolic and inverse hyperbolic functions.

---

### `floor(x)` / `ceiling(x)` / `ceil(x)`

Rounding to integers. `ceiling` and `ceil` are aliases.

---

### `round(x, digits = 0)` / `signif(x, digits = 6)`

Rounding to decimal places or significant figures.

---

### `trunc(x)` / `sign(x)`

Truncate fractional part or get the sign (-1, 0, 1) of a value.

---

### `ndarray(data, shape = NA)` / `reshape(array, shape)`

Create or reshape N-dimensional arrays. `ndarray` can infer shape from nested lists.

---

### `shape(array)` / `ndarray_data(array)`

Get NDArray dimensions (as a List) or flat data (as a List of Floats).

---

### `matmul(a, b)` / `inv(matrix)` / `transpose(matrix)`

Linear algebra operations on 2D NDArrays.

---

### `diag(x)` / `kron(a, b)` / `cbind(a, b)`

Matrix creation and manipulation. `diag` extracts the diagonal from a 2D array or creates a diagonal matrix from a 1D array.

---

### `iota(n)`

Returns a Vector of length `n` filled with `1.0` (a ones vector). Useful for initializing weights or masks.

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

Statistical functions for data analysis. Most functions handle missingness via an `na_rm` parameter.

### Descriptive Statistics

#### `median(x, na_rm = false)` / `mean(x, na_rm = false)`
#### `min(x, na_rm = false)` / `max(x, na_rm = false)` / `range(x, na_rm = false)`

Basic descriptive statistics. `range` returns a List of [min, max].

---

#### `var(x, na_rm = false)` / `sd(x, na_rm = false)` / `cv(x, na_rm = false)`

Variance, standard deviation, and coefficient of variation (sd/mean).

---

#### `iqr(x, na_rm = false)` / `mad(x, na_rm = false)`

Interquartile range and Median Absolute Deviation (scaled by 1.4826).

---

#### `fivenum(x, na_rm = false)`

Tukey's five-number summary (min, lower-hinge, median, upper-hinge, max).

---

#### `skewness(x, na_rm = false)` / `kurtosis(x, na_rm = false)`

Skewness and excess kurtosis.

---

#### `trimmed_mean(x, trim = 0.1, na_rm = false)`

Mean calculated after trimming a fraction of observations from each end.

---

#### `quantile(x, p, na_rm = false)`

Compute quantile/percentile (p between 0 and 1).

---

#### `mode(x)`

Return the most frequent value. Does not currently support `na_rm`.

---

### Data Transformation

#### `normalize(x)` / `standardize(x)` / `scale(x)`

Rescale or center numeric data. `scale` and `standardize` compute z-scores. `normalize` scales to [0, 1].

---

#### `winsorize(x, probs = [0.05, 0.95], na_rm = false)`

Replace extreme values with quantiles.

---

#### `huber_loss(actual, predicted, delta = 1.0)`

Compute the Huber loss between two vectors.

---

### Distributions (CDFs)

#### `pnorm(x)` / `pt(x, df)` / `pf(q, df1, df2)` / `pchisq(q, df)`

Cumulative Distribution Functions for Normal, Student-t, F, and Chi-squared distributions.

---

### Modeling

#### `lm(data, formula)`

Fit a linear regression model (OLS). The formula is a string like `"mpg ~ wt + hp"`.

---

#### `summary(model)` / `fit_stats(model)`

Extract tidy coefficients (DataFrame) or model-level metrics (Dict).

---

#### `predict(data, model)` / `score(data, model)`

Perform vectorized prediction on new data. `score` is an alias.

---

#### `add_diagnostics(model, data)` / `augment(model, data)`

Augment data with per-observation diagnostics: `.fitted`, `.resid`, `.hat`, `.sigma`, `.cooksd`, and `.std.resid`.

---

#### `anova(model1, model2, ...)`

Compare multiple nested models using an ANOVA table.

---

#### `coef(model)` / `residuals(model)` / `vcov(model)` / `df_residual(model)`

Extract model components.

---

#### `wald_test(model, terms)`

Perform a Wald test for a joint hypothesis on coefficients.

---

#### `read_onnx(path)` / `read_pmml(path)`

Import pre-trained models from ONNX or PMML formats for native scoring.

---

### `cut(x, breaks, ...)` / `poly(x, degree, ...)`

Basis functions for modeling.

---


---

## DataFrame Package

CSV I/O and DataFrame introspection.

### `dataframe(data)`

Constructs a DataFrame from either a list of rows (Dictionaries) or a Dictionary of columns (Vectors/Lists).

**Parameters:**

- `data` — List of Dictionaries (row-wise) or a single Dictionary (column-wise)

**Returns:**

`DataFrame`

**Examples:**
```t
-- Column-wise
df = dataframe([x: [1, 2], y: [3, 4]])

-- Row-wise
df = dataframe([
  [name: "Alice", age: 30],
  [name: "Bob", age: 25]
])
```

---

### `read_csv(path, separator = ",", skip_lines = 0, skip_header = false, clean_colnames = false)`

Read a CSV file into a DataFrame.

**Parameters:**


- `path` — File path (String)
- `separator` (optional) — Column separator (default: ",")
- `skip_lines` (optional) — Number of lines to skip at start (default: 0)
- `skip_header` (optional) — If true, treat first row as data (default: false)
- `clean_colnames` (optional) — If true, normalize column names (default: false)

**Returns:**

`DataFrame`

---

### `read_parquet(path)`

Read a Parquet file into a DataFrame.

---

### `read_arrow(path)` / `write_arrow(dataframe, path)`

Read or write Arrow IPC files.

---

### `write_csv(dataframe, path, separator = ",")`

Write a DataFrame to a CSV file.

---

### `nrow(dataframe)` / `ncol(dataframe)`

Get number of rows or columns.

---

### `colnames(dataframe)`

Get column names as a List of strings.

---

### `clean_colnames(x)`

Standardizes column names using a snake_case convention. Works on DataFrames or Lists of strings.

---

### `glimpse(dataframe)`

Prints a summary of the DataFrame structure, including dimensions, column names, types, and first few values.

---

### `pull(dataframe, column)`

Extracts a single column as a Vector.

---

### `to_array(dataframe, columns = NA)`

Converts numeric columns of a DataFrame to a matrix (NDArray).

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

### Join and Bind Functions

#### `left_join(x, y, by = NA)` / `inner_join` / `full_join` / `semi_join` / `anti_join`

Join two DataFrames.

**Parameters:**

- `x`, `y` — DataFrames to join
- `by` (optional) — Column(s) to join on. If omitted, uses common columns.

**Returns:**

Joined DataFrame

---

#### `bind_rows(...)` / `bind_cols(...)`

Combine multiple DataFrames by stacking rows or placing columns side-by-side.

---

### Wrangling Utilities

#### `count(df, ...columns)`

Count occurrences of unique values.

---

#### `distinct(df, ...columns)`

Keep only unique rows.

---

#### `drop_na(df, ...columns)`

Drop rows containing NA values in the specified columns.

---

#### `replace_na(df, values)`

Replace NA values with specified defaults.

---

#### `rename(df, ...new_name = old_name)`

Rename columns.

---

#### `relocate(df, ...columns, before = NA, after = NA)`

Change column order.

---

#### `slice(df, ...indices)` / `slice_min(df, col, n = 1)` / `slice_max(df, col, n = 1)`

Subset rows by position or extreme values.

---

#### `pivot_longer(df, cols, names_to = "name", values_to = "value")`
#### `pivot_wider(df, names_from = "name", values_from = "value")`

Reshape DataFrames between long and wide formats.

---

#### `separate(df, col, into, sep = "[^a-zA-Z0-9]+")` / `unite(df, col, ...from, sep = "_")`

Split a column into multiple columns, or combine multiple columns into one.

---

### Factor Manipulation

#### `factor(x, levels = NA, ordered = false)` / `fct(x)` / `as_factor(x)`

Create factor-encoded vectors. `fct` uses first-appearance levels by default.

---

#### `levels(f)`

Get labels from a factor.

---

#### `fct_recode(f, ...new = old)` / `fct_relevel(f, ...levels, after = 0)`

Rename or reorder factor levels.

---

#### `fct_lump_n(f, n, other_level = "Other")` / `fct_lump_min` / `fct_lump_prop`

Collapse infrequent levels into an "Other" category.

---

#### `fct_infreq(f)` / `fct_rev(f)` / `fct_reorder(f, x, .desc = false)`

Reorder levels by frequency, reversal, or summary of another vector.

---

### Aggregation Context

#### `n()`

Returns the number of rows in the current group. Only valid inside `summarize()`.

---

#### `n_distinct(x)`

Returns the number of unique non-NA values.

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

### `ymd(string)` / `mdy(string)` / `dmy(string)` / `ydm(string)`
### `ymd_h(string)` / `ymd_hm(string)` / `ymd_hms(string)`

Parse strings into dates or datetimes using common layouts.

**Parameters:**

- `string` — Date or Datetime string

**Returns:**

`Date` / `Datetime`

**Examples:**
```t
ymd("2023-05-15")
mdy("05-15-2023")
ymd_hms("2023-05-15 14:30:05")
```

---

### `parse_date(string, format)` / `parse_datetime(string, format, tz = "UTC")`

Parse strings into temporal values using explicit `strptime`-style formats.

**Parameters:**

- `string` — Input string
- `format` — Format string (e.g., "%Y-%m-%d")
- `tz` (optional) — Timezone label for `parse_datetime`

**Returns:**

`Date` / `Datetime`

---

### `today()` / `now(tz = "UTC")`

Get the current UTC date or datetime.

**Returns:**

`Date` / `Datetime`

---

### `year(x)` / `month(x, label = false)` / `day(x)` / `mday(x)`
### `yday(x)` / `wday(x, label = false, week_start = 7)` / `week(x)` / `isoweek(x)` / `isoyear(x)`
### `quarter(x)` / `semester(x)`

Extract calendar components from Date or Datetime values.

**Parameters:**

- `x` — Date or Datetime
- `label` (optional) — If true, returns month/weekday names as strings.
- `week_start` (optional) — Day the week starts on (1=Mon, 7=Sun).

**Returns:**

`Int` / `String`

---

### `hour(x)` / `minute(x)` / `second(x)` / `tz(x)`

Extract time-of-day components or timezone labels from Datetime values.

**Returns:**

`Int` / `Float` / `String`

---

### `am(x)` / `pm(x)`

Check whether a time is before or after noon.

**Returns:**

`Bool`

---

### `floor_date(datetime, unit)` / `ceiling_date(datetime, unit)` / `round_date(datetime, unit)`

Round a date/datetime to the nearest unit boundary (year, month, day, hour, etc.).

**Parameters:**

- `datetime` — Date or Datetime
- `unit` — Unit as string ("month", "day", "hour", etc.)

**Returns:**

Same as input type

**Examples:**
```t
floor_date(as_date("2023-05-15"), "month")  -- 2023-05-01
```

---

### `make_date(year, month, day)` / `make_datetime(year, month, day, hour, min, sec, tz)`

Construct temporal values from numeric components.

---

### `format_date(x, format)` / `format_datetime(x, format)`

Format temporal values as strings using `strftime`-style patterns.

---

### `interval(start, end)` / `%within%(x, interval)`

Construct temporal intervals and test membership.

---

### `years(n)` / `months(n)` / `weeks(n)` / `days(n)` / `hours(n)` / `minutes(n)` / `seconds(n)`

Construct Period objects for date arithmetic.

---

### `is_date(x)` / `is_datetime(x)` / `is_period(x)` / `is_duration(x)` / `is_interval(x)`

Type predicates for temporal values.

---

### `is_leap_year(x)` / `days_in_month(x)`

Calendar helpers.

---

### `with_tz(x, tz)` / `force_tz(x, tz)`

Update the timezone label of a Datetime value.

---

## Strcraft Package

Modern string manipulation utilities, inspired by R's `stringr`.

### `str_replace(string, pattern, replacement)` / `replace_first(string, pattern, replacement)`

Replace occurrences of a pattern. `str_replace` replaces **all** occurrences (global replace); `replace_first` replaces only the first occurrence.

---

### `str_detect(string, pattern)` / `contains(s, sub)`

Check if a pattern or substring exists.

---

### `starts_with(s, prefix)` / `ends_with(s, suffix)`

Check string boundaries.

---

### `str_extract(s, pattern)` / `str_extract_all(s, pattern)`

Extract matching substrings. `str_extract` returns the first match; `str_extract_all` returns a List of all matches.

---

### `str_count(s, pattern)` / `str_nchar(s)`

Count matches or total characters.

---

### `str_trim(s)` / `trim_start(s)` / `trim_end(s)`

Remove whitespace.

---

### `str_lines(s)` / `str_words(s)` / `str_split(s, sep)`

Split strings into parts. `str_lines` splits on newlines; `str_words` splits on any whitespace.

---

### `str_pad(s, width, side = "left", pad = " ")`

Pad strings to a fixed width.

---

### `str_trunc(s, width, side = "right", ellipsis = "...")`

Truncate strings with an ellipsis.

---

### `str_flatten(values, collapse = "")` / `str_join(items, sep = "")`

Combine multiple strings into one.

---

### `to_lower(s)` / `to_upper(s)`

Case normalization.

---

### `str_repeat(s, n)`

Repeat a string `n` times.

---

### `str_format(fmt, values)` / `str_sprintf(fmt, ...)`

String interpolation and formatting. `str_format` uses `{name}` placeholders with a Dictionary or named List; `str_sprintf` uses C-style `%` specifiers.

---

---

## Lens Package

Composable access and update lenses for dictionaries, lists, data frames, and pipeline inspection.

For the full walkthrough and worked examples, see the [Lens guide](lens.md). For the generated per-function entries, see the [Function Reference](reference/index.md).

### `col_lens(name)` / `idx_lens(i)` / `row_lens(i)`

Focus on a dictionary key/column, a list index, or a DataFrame row.

---

### `filter_lens(predicate)`

Focus on elements matching a predicate (supports DataFrames, Lists, and Vectors).

---

### `node_lens(name)` / `node_meta_lens(name, field)` / `env_var_lens(node, var)`

Focus on pipeline nodes, their metadata, or environment variables.

---

### `compose(...lenses)`

Combine multiple lenses into a deep traversal.

---

### `get(data, lens)` / `set(data, lens, value)` / `over(data, lens, fn)`

Read, write, or transform data at the focused location.

---

### `modify(data, ...pairs)`

Apply a sequence of `(lens, function)` pairs to the same data structure.

---

## Pipeline Package

Pipeline introspection and management.

### `pipeline(...)`

Constructs a Pipeline from a Dictionary of named nodes or a List of node records.

---

### `build_pipeline(p, verbose = 0)` / `populate_pipeline(p, build = true)`

Materialize a pipeline to Nix artifacts. `build_pipeline` is the primary entry point for full Nix builds. `populate_pipeline` can be used to generate the Nix expression without building (with `build = false`).

---

### `read_pipeline(p)` / `inspect_pipeline(p)`

Returns a dictionary with node metadata and diagnostics summary. `inspect_pipeline` focuses on the DAG structure (edges).

---

### `read_node(node, name = NA, which_log = NA)`

Retrieves a node artifact. Supports in-memory Pipelines (needs `name`), built node names (String), or ComputedNode objects.

---

### `filter_node(p, predicate)` / `select_node(p, ...)`

Subsetting nodes in a pipeline. `filter_node` keeps nodes matching a condition; `select_node` picks nodes by name.

---

### `mutate_node(p, ...)` / `rename_node(p, ...)`

Modify nodes within a pipeline. `mutate_node` can redefine or add nodes; `rename_node` changes node labels while preserving dependencies.

---

### `arrange_node(p, ...)`

Reorders nodes in the pipeline definition (does not affect execution order, which is DAG-driven).

---

### `trace_nodes(p, node_names)`

Returns a sub-pipeline containing only the specified nodes and all their recursive dependencies.

---

### `which_nodes(p, predicate)`

Filter the richer node records from `read_pipeline(p).nodes` without manually writing `read_pipeline`, `compose`, or an explicit lambda.

---

### `errored_nodes(p)`

Convenience wrapper returning the subset of node records whose `diagnostics.error` is not `NA`.

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

### `qn(script = NA, serializer = "default", deserializer = "default", env_vars = [:], args = [:], functions = [], include = [], noop = false)`

Configure a Quarto pipeline node. A convenience wrapper around `node()` with `runtime = "Quarto"`. Use it to render `.qmd` files inside `pipeline { ... }` blocks.

**Parameters:**

- `script` (optional) — Path to an external `.qmd` file. Mutually exclusive with `command`.
- `serializer` (optional) — Custom serializer function. Default: `default`.
- `deserializer` (optional) — Custom deserializer function. Default: `default`.
- `env_vars` (optional) — Dictionary of environment variables to pass into the Nix sandbox.
- `args` (optional) — Runtime/tool arguments for Quarto, such as `subcommand`, `path`, `to`, and other CLI options.
- `functions` (optional) — Files to source before execution.
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

### `suppress_warnings(value)`

Silence diagnostic warnings for a pipeline node while maintaining auditability in the background metadata.

**Parameters:**

- `value` — The expression or value to wrap (usually at the end of a node definition).

**Returns:**

The original `value`, but with a signal to the evaluator to suppress console warnings for the currently executing node.

**Examples:**

```t
p = pipeline {
  -- Silence warnings from a high-noise filter
  filtered = raw 
    |> filter($amount > 100) 
    |> suppress_warnings
}
```

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

Get detailed explanation of a value. For DataFrames, returns a compact summary by default showing `kind`, `nrow`, `ncol`, and a `hint`. Detailed fields (`schema`, `na_stats`, `example_rows`) are accessible via dot notation. For pipeline node results returned by `read_node(...)`, `explain()` now returns a top-level node wrapper with `kind`, `node_name`, `diagnostics`, and `contents`. The `contents` field is the explained payload stored in the node. In the REPL and CLI `t explain ...`, explain output is shown with a tree-style formatter for readability, but the runtime value remains a normal `Dict`.

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

node_info = explain(read_node("model"))
node_info.node_name       -- node/container metadata
node_info.diagnostics     -- node diagnostics
node_info.contents        -- explained node payload
```

---

### `explain_json(value)`

Returns a JSON string representation of the `explain` output.

---

### `intent_fields(intent)` / `intent_get(intent, key)`

Access metadata fields from an Intent object (e.g. from an `intent { ... }` block).

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
