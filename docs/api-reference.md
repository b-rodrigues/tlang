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
- [DataFrame Package](#to_dataframe-package) — CSV I/O and DataFrame operations
- [Colcraft Package](#colcraft-package) — Data manipulation verbs and window functions
- [Chrono Package](#chrono-package) — High-performance date and time manipulation
- [Strcraft Package](#strcraft-package) — Modern string manipulation
- [Lens Package](#lens-package) — Composable access and update lenses
- [Pipeline Package](#pipeline-package) — Pipeline introspection
- [Explain Package](#explain-package) — Introspection and debugging tools
- [Testcraft Package](#testcraft-package) — Unit-testing primitives

---

For generated one-page documentation for every exported function, including newer Chrono, string, join, to_factor, and helper APIs, use the [Function Reference](reference/index.md).

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

### `to_float(value)` / `to_float(value)`

Convert a value to a float robustly. `to_float` is an alias for `to_float`. Handles strings with spaces, percentages, commas, and recognizes 'TRUE'/'FALSE'. Also propagates vectorization over Collections.

**Parameters:**


- `value` — Any value (String, Bool, Int, List, Vector)

**Returns:**

`Float`, `NA`, or a Collection of `Float`/`NA`

**Examples:**
```t
to_float("3,14")         -- 3.14
to_float("15%")          -- 15.0
to_float(" 1 200.5 ")    -- 1200.5
to_float("TRUE")       -- 1.0
to_float("F")          -- 0.0
to_float(42)             -- 42.0
to_float("hello")        -- NA(Float)
to_float(["1", "2"])   -- [1.0, 2.0]
```

---

### `to_symbol(value)`

Convert a string name into a `Symbol` so it can be injected into quoted code with `!!`. Existing symbols pass through unchanged.

**Parameters:**


- `value` — String or Symbol

**Returns:**

`Symbol`

**Examples:**
```t
to_symbol("mpg")                           -- mpg
to_expr(select(df, !!to_symbol("mpg")))       -- to_expr(select(df, mpg))
name = "result"
to_expr(f(!!to_symbol(name) := 42))           -- to_expr(f(result = 42))
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

When called with a single string or symbol argument inside an NSE data verb (`mutate`, `filter`, `summarize`, …), `get()` checks the **data mask** first: if the name matches a column in the current row or DataFrame, the column value is returned; otherwise it falls back to the global environment.

**Examples:**
```t
get("salary")                -- variable lookup
get(list, 0)                  -- indexing
get(df, col_lens("mpg"))      -- lens focus
get(val, 0)                   -- fallback if val is NA/Error

-- Data-mask aware: column lookup inside mutate
x = 42
df = dataframe(a = [1, 2, 3])
df |> mutate(b = \(row) get("a"))  -- column "a" from data mask
df |> mutate(c = \(row) get("x"))  -- "x" not a column, falls back to global
```

---

### `ifelse(condition, true_val, false_val, missing = NA, out_type = NA)`

Vectorized conditional selection.

---

### `case_when(...formulas, .default = NA)`

Vectorized multi-condition switch. Uses `condition ~ value` formulas.

---

### `identical(a, b)`

Deep equality check. Works for collections and complex objects.

---

### `node_when(condition, value)`

Static conditional for pipeline nodes. Evaluated at pipeline construction time.
Returns `value` if `condition` is truthy, otherwise excludes the node from the DAG.

`node_when` is only meaningful as the direct value of a node binding inside a
`pipeline { }` block. Using the result outside that context (arithmetic,
`is_na()`, etc.) is unsupported.

### `node_fork(...condition_value_pairs, .default = ...)`

Static multi-way branch for pipeline nodes. Returns the value for the first
truthy condition-value pair. If no condition matches and `.default` is provided,
that value is included in the pipeline; if `.default` is omitted the node is
excluded from the DAG entirely (null marker behaviour, not `NA`).

`node_fork` is only meaningful as the direct value of a node binding inside a
`pipeline { }` block. Using the result outside that context is unsupported.

---

### `eval(expr)` / `to_expr(x)` / `to_exprs(...)`
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

Display a built or unbuilt R/Python/Julia plot node (depends on the environment's plot viewer).

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

### `float_seq(start, end, n = 100)`

Generate a sequence of evenly-spaced floats.

**Parameters:**

- `start` — Starting value (Float or Int)
- `end` — Ending value (Float or Int)
- `n` (optional) — Number of values (default: 100)

**Returns:**

List of evenly-spaced floats.

**Examples:**
```t
float_seq(0, 1, 5)              -- [0.0, 0.25, 0.5, 0.75, 1.0]
float_seq(start = 0, end = 1, n = 5)
```

---

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
error_msg(e)  -- "custom error"
```

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

### `error_msg(err)`

Get the error message from an Error value.

**Parameters:**


- `err` — Error value

**Returns:**

`String` — Error message

**Examples:**
```t
e = error("Something broke")
error_msg(e)  -- "Something broke"

e2 = 1 / 0
error_msg(e2)  -- "Division by zero"
```

---

### `warning_msg(node)`

Get the warning message from a completed computed node (if any exists). Downstream nodes automatically inherit warnings from ancestor nodes, with each upstream warning prefixed by its source node name for clear provenance.

**Parameters:**


- `node` — ComputedNode value

**Returns:**

`String` — Warning message, or an empty string `""` if there are no warnings. Upstream warnings are prefixed with `"Ancestor node '<name>' reported following warning: <message>"`. Multiple warnings are joined with `". Furthermore, "`.

**Examples:**
```t
p = pipeline { a = suppress_warnings(node()) }
build_pipeline(p)
warning_msg(p.a)  -- Returns warning message string or ""
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


### `error_chain(err1, err2)`

Explicitly chains two Error values together to preserve their provenance. This sets `err2` as the underlying cause in `err1`'s context.

**Parameters:**

- `err1` — The primary or outer Error value.
- `err2` — The underlying cause Error value.

**Returns:**

`Error` — The chained Error value.

**Examples:**
```t
err1 = error("Primary calculation failed")
err2 = error("KeyError", "Missing key 'x'")
chained = error_chain(err1, err2)

error_context(chained)$cause  -- Returns err2
```

---

### `set_seed(seed)`

Initializes the global random number generator with a given integer seed, enabling reproducible random draws from `sample()` and `slice_sample()`.

**Parameters:**

- `seed` — Integer seed value.

**Returns:**

`NA`

**Examples:**
```t
set_seed(42)
sample([1, 2, 3, 4, 5], n = 3)
```

---

### `sample(x, n = 1, replace = false)`

Draw a random sample of size n from a Vector or List, with or without replacement.

**Parameters:**

- `x` — `Vector` or `List` of values to sample from.
- `n` (optional) — Number of elements to draw. Default `1`.
- `replace` (optional) — Whether to sample with replacement. Default `false`.

**Returns:**

`Vector` or `List` (matching input type)

**Examples:**
```t
sample([10, 20, 30, 40, 50], n = 2)
sample([1, 2, 3], n = 5, replace = true)
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

### `assert_file_exists(path)` / `assert_file_exists(path, message)`

Assert that a regular file exists at `path`.

**Parameters:**

- `path` — File path
- `message` (optional) — Custom assertion message

**Returns:**

`true` if the file exists

**Examples:**
```t
assert_file_exists("output.csv")
assert_file_exists("report.html", "report generation failed")
```

---

### `assert_dir_exists(path)` / `assert_dir_exists(path, message)`

Assert that a directory exists at `path`.

**Parameters:**

- `path` — Directory path
- `message` (optional) — Custom assertion message

**Returns:**

`true` if the directory exists

**Examples:**
```t
assert_dir_exists("results")
assert_dir_exists("artifacts", "artifact directory was not created")
```

---

### `assert_size_of_file(path, size)` / `assert_size_of_file(path, size, message)`

Assert that a regular file exists and has the expected size in bytes.

**Parameters:**

- `path` — File path
- `size` — Expected size in bytes
- `message` (optional) — Custom assertion message

**Returns:**

`true` if the file exists and matches the expected size

**Examples:**
```t
assert_size_of_file("output.csv", 128)
assert_size_of_file("report.html", 0, "report should be empty")
```

---

### `assert_non_empty_file(path)` / `assert_non_empty_file(path, message)`

Assert that a regular file exists and contains at least one byte.

**Parameters:**

- `path` — File path
- `message` (optional) — Custom assertion message

**Returns:**

`true` if the file exists and is non-empty

**Examples:**
```t
assert_non_empty_file("output.csv")
assert_non_empty_file("plot.png", "plot was not written")
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

### `fetchurl(url, sha256?, output?, dest?)`

Downloads a file from a URL. In the REPL, wraps curl for immediate download. Inside a pipeline, creates a node that uses Nix's `builtins.fetchurl` to fetch the asset into the Nix store, making it available downstream.

**Parameters:**

- `url` — The URL to download (String)
- `sha256` (optional) — Expected SHA-256 hash (String). Required in pipeline mode.
- `output` (optional) — Output file path for REPL mode (String). Defaults to basename of URL.
- `dest` (optional) — Output directory for REPL mode (String). Defaults to current directory.

**Returns:**

`String` (REPL mode) — The path to the downloaded file.
`Node` (pipeline mode) — A pipeline node configured to fetch the URL via Nix.

**Examples:**
```t
-- REPL mode: download to current directory
data = fetchurl("https://example.com/data.csv", output = "data.csv")

-- Pipeline mode: fetch via Nix builtins.fetchurl
p = pipeline {
  raw = fetchurl("https://example.com/data.csv", sha256 = "abc123...");
  result = read_csv(raw) |> mutate(...);
}
build_pipeline(p)
```

---

### `prefetch(url)`

Downloads a URL and computes its SHA-256 hash. Useful for obtaining the hash needed by `fetchurl` in pipeline mode.

**Parameters:**

- `url` — The URL to prefetch (String)

**Returns:**

`String` — The SHA-256 hex digest of the downloaded content.

**Examples:**
```t
hash = prefetch("https://example.com/data.csv")
print(hash)  -- e.g. "abc123..."
```

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

### `floor(x)` / `ceiling(x)` / `ceiling(x)`

Rounding to integers. `ceiling` and `ceiling` are aliases.

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

---

## Stats Package

Statistical functions for data analysis. Most functions handle missingness via an `na_rm` parameter.

### Descriptive Statistics

#### `median(x, na_rm = false, weights = NA)` / `mean(x, na_rm = false, weights = NA)`
#### `min(x, na_rm = false)` / `max(x, na_rm = false)` / `range(x, na_rm = false)`

Basic descriptive statistics. `mean` and `median` also accept optional non-negative observation weights. `range` returns a List of [min, max].

---

#### `var(x, na_rm = false, weights = NA)` / `sd(x, na_rm = false, weights = NA)` / `cv(x, na_rm = false, weights = NA)`

Variance, standard deviation, and coefficient of variation (sd/mean). These also accept optional non-negative observation weights. The weighted `sd`/`var` path uses the weighted population denominator (`sum(weights)`), while the unweighted path uses sample formulas.

---

#### `iqr(x, na_rm = false, weights = NA)` / `mad(x, na_rm = false)`

Interquartile range and Median Absolute Deviation (scaled by 1.4826). `iqr` accepts optional non-negative observation weights.

---

#### `fivenum(x, na_rm = false, weights = NA)`

Tukey's five-number summary (min, lower-hinge, median, upper-hinge, max), with optional non-negative observation weights.

---

#### `skewness(x, na_rm = false, weights = NA)` / `kurtosis(x, na_rm = false, weights = NA)`

Skewness and excess kurtosis, with optional non-negative observation weights.

---

#### `trimmed_mean(x, trim = 0.1, na_rm = false, weights = NA)`

Mean calculated after trimming a fraction of observations from each end. Optional weights affect the trim cut points and the retained mean.

---

#### `quantile(x, p, na_rm = false, weights = NA)`

Compute quantile/percentile (p between 0 and 1), with optional non-negative observation weights.

---

#### `mode(x)`

Return the most frequent value. Does not currently support `na_rm`.

---

### Data Transformation

#### `normalize(x)` / `standardize(x)` / `scale(x)`

Rescale or center numeric data. `scale` and `standardize` compute z-scores. `normalize` scales to [0, 1].

---

#### `winsorize(x, limits = [0.05, 0.05], na_rm = false, weights = NA)`

Clamp values using one limit or a two-element vector `[lower_tail_fraction, upper_tail_fraction]`, with each fraction in `[0, 0.5)`. Optional weights affect the cut points only; zero-weight observations remain in the output.

---

#### `huber_loss(actual, predicted, delta = 1.0)`

Compute the Huber loss between two vectors.

---

### Distributions (CDFs)

#### `pnorm(x)` / `pt(x, df)` / `pf(q, df1, df2)` / `pchisq(q, df)`

Cumulative Distribution Functions for Normal, Student-t, F, and Chi-squared distributions.

---

### Quantile Functions (Inverse CDFs)

#### `qnorm(p, mean=0, sd=1)` / `qt(p, df)` / `qf(p, df1, df2)` / `qchisq(p, df)`

Quantile (inverse cumulative probability) Functions for Normal, Student-t, F, and Chi-squared distributions.

- `qnorm(p, mean = 0, sd = 1)` — normal quantile with optional `mean` and `sd` named args.
- `qt(p, df)` — Student t quantile.
- `qf(p, df1, df2)` — F quantile.
- `qchisq(p, df)` — Chi-squared quantile.

---

### Modeling

#### `lm(data, formula, weights = NA)`

Fit a linear regression model. Without weights this is OLS; with `weights` it performs weighted least squares. The formula is a `Formula` value such as `mpg ~ wt + hp`.

---

#### `summary(model)` / `fit_stats(model)`

`summary(model)` returns a `Dict` containing a `_tidy_df` DataFrame plus metadata; `fit_stats(model)` returns a `DataFrame` of model-level metrics.

---

#### `predict(data, model)` / `score(data, model)`

Perform vectorized prediction on new data. `score` is an alias.

---

#### `add_diagnostics(model, data)` / `add_diagnostics(model, data)`

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

#### `t_read_onnx(path)` / `t_read_pmml(path)`

Import pre-trained models from ONNX or PMML formats for native scoring.
Julia nodes can also consume `^onnx` artifacts through `ONNXRunTime.jl`; ONNX export from Julia remains explicitly unsupported.

---

### `cut(x, breaks, ...)` / `poly(x, degree, ...)`

Basis functions for modeling.

---


---

## DataFrame Package

CSV I/O and DataFrame introspection.

### `to_dataframe(data)`

Constructs a DataFrame from either a list of rows (Dictionaries) or a Dictionary of columns (Vectors/Lists).

**Parameters:**

- `data` — List of Dictionaries (row-wise) or a single Dictionary (column-wise)

**Returns:**

`DataFrame`

**Examples:**
```t
-- Column-wise
df = to_dataframe([x: [1, 2], y: [3, 4]])

-- Row-wise
df = to_dataframe([
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

### `read_parquet(path)` / `write_parquet(to_dataframe, path)`

Read or write Parquet files using the native parquet-glib reader/writer.

---

### `read_arrow(path)` / `write_arrow(to_dataframe, path)`

Read or write Arrow IPC files.

---

### `write_csv(to_dataframe, path, separator = ",")`

Write a DataFrame to a CSV file.

---

### `nrow(to_dataframe)` / `ncol(to_dataframe)`

Get number of rows or columns.

---

### `colnames(to_dataframe)`

Get column names as a List of strings.

---

### `clean_colnames(x)`

Standardizes column names using a snake_case convention. Works on DataFrames or Lists of strings.

---

### `glimpse(to_dataframe)`

Prints a summary of the DataFrame structure, including dimensions, column names, types, and first few values.

---

### `pull(to_dataframe, column)`

Extracts a single column as a Vector.

---

### `to_array(to_dataframe, columns = NA)`

Converts numeric columns of a DataFrame to a matrix (NDArray).

---

### `ncol(to_dataframe)`

Get number of columns.

**Parameters:**


- `to_dataframe` — DataFrame

**Returns:**

`Int` — Column count

**Examples:**
```t
ncol(df)  -- 5
```

---

### `colnames(to_dataframe)`

Get column names.

**Parameters:**


- `to_dataframe` — DataFrame

**Returns:**

List of Strings

**Examples:**
```t
colnames(df)  -- ["name", "age", "dept", "salary"]
```

---

### `glimpse(to_dataframe)`

Get a compact overview of a DataFrame, showing column names, types, and example values. Similar to dplyr's `glimpse()`.

**Parameters:**


- `to_dataframe` — DataFrame

**Returns:**

Dict with `kind`, `nrow`, `ncol`, and `columns` (list of column summaries)

**Examples:**
```t
glimpse(df)
-- {`kind`: "to_dataframe", `nrow`: 100, `ncol`: 4, `columns`: ["name <String> ...", "age <Int> ...", ...]}
```

---

### `clean_colnames(to_dataframe)` / `clean_colnames(names)`

Normalize column names to safe identifiers.

**Parameters:**


- `to_dataframe` — DataFrame, OR
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

#### `select(to_dataframe, ...columns)`

Select columns by name. Supports dollar-prefix NSE syntax.

**Parameters:**


- `to_dataframe` — DataFrame
- `...columns` — Column references (`$name`)

**Returns:**

DataFrame with selected columns

**Examples:**
```t
df |> select($name, $age)
df |> select($dept)
```

---

#### `filter(to_dataframe, predicate)`

Filter rows by condition. Supports NSE expressions with dollar-prefix column references.

**Parameters:**


- `to_dataframe` — DataFrame
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

#### `mutate(to_dataframe, $col = expr)` / `mutate(to_dataframe, new_col, fn)`

Add or transform a column. Supports `$col = expr` named-arg syntax with NSE.

**Parameters (named-arg form):**
- `to_dataframe` — DataFrame
- `$col = expr` — Column name from `$col`, value from NSE expression

**Parameters (positional form):**
- `to_dataframe` — DataFrame
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

#### `arrange(to_dataframe, column, direction = "asc")`

Sort rows by column. Supports dollar-prefix NSE for column names.

**Parameters:**


- `to_dataframe` — DataFrame
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

#### `group_by(to_dataframe, ...columns)`

Group by one or more columns. Supports dollar-prefix NSE for column names.

**Parameters:**


- `to_dataframe` — DataFrame
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

#### `slice(df, ...indices)` / `slice_min(df, col, n = 1)` / `slice_max(df, col, n = 1)` / `slice_sample(df, n = 1, replace = false)`

Subset rows by position, extreme values, or random sample. `slice_sample` draws a random sample of n rows with or without replacement. Use `set_seed()` for reproducible results.

---

#### `pivot_longer(df, cols, names_to = "name", values_to = "value")`
#### `pivot_wider(df, names_from = "name", values_from = "value")`

Reshape DataFrames between long and wide formats.

---

#### `separate(df, col, into, sep = "[^a-zA-Z0-9]+")` / `unite(df, col, ...from, sep = "_")`

Split a column into multiple columns, or combine multiple columns into one.

---

### Factor Manipulation

#### `to_factor(x, levels = NA, ordered = false)`

Create to_factor-encoded vectors. Derives unique levels alphabetically if `levels` is not provided.

---

#### `levels(f)`

Get labels from a to_factor.

---

#### `fct_recode(f, ...new = old)` / `fct_relevel(f, ...levels, after = 0)`

Rename or reorder to_factor levels.

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

### `to_date(value)` / `to_datetime(value)`

Convert values to Date or Datetime types.

**Parameters:**

- `value` — String, Number, or Collection of values

**Returns:**

`Date` / `Datetime` / `Collection`

**Examples:**
```t
to_date("2023-05-15")  -- 2023-05-15
to_datetime("2023-05-15 14:00:00")
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

### `year(x)` / `month(x, label = false)` / `day(x)` / `day(x)`
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
floor_date(to_date("2023-05-15"), "month")  -- 2023-05-01
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

### `build_pipeline(p, verbose = 0, pipeline_name = NA)` / `populate_pipeline(p, build = true)`

Materialize a pipeline to Nix artifacts. `build_pipeline` is the primary entry point for full Nix builds and returns a `BuildLog` value (`nodes`, `duration`, `failed_nodes`, `out_path`). `populate_pipeline` can be used to generate the Nix expression without building (with `build = false`). Use `pipeline_name` to record a name in the build log for later disambiguation via `list_logs()`.

---

### `read_pipeline(p)` / `inspect_pipeline(p)`

Returns a dictionary with node metadata and diagnostics summary. `inspect_pipeline` focuses on the DAG structure (edges).

---

### `read_node(node)`

Retrieves the dynamically evaluated or built artifact of a node from an in-scope pipeline. Strictly expects a `ComputedNode` object (e.g. `p.node_name`). For reading from historical build logs without the pipeline in scope, use [`read_past_node(p.node_name, which_log = ...)`](#read_past_node).

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

---

### `pipeline_to_ga(p, name = NA, pipeline_script = "src/pipeline.t", file = NA)`

Generates a GitHub Actions CI workflow YAML to run the pipeline on push/PR events. It integrates with Cachix (`rstats-on-nix`) and caches built Nix artifacts inside the repository's `t-runs` branch as `.nar` archives.

**Parameters:**

- `p` — The Pipeline to configure.
- `name` (optional) — Project name (auto-detected from `tproject.toml` if omitted).
- `pipeline_script` (optional) — Path to the pipeline T script (default: `"src/pipeline.t"`).
- `file` (optional) — Output file path. If specified, writes the YAML directly to that file (usually `.github/workflows/<name>.yml`); if omitted, returns the workflow YAML content as a String.

**Returns:**

String (workflow YAML content or file write success message).

**Examples:**
```t
pipeline_to_ga(p)
pipeline_to_ga(p, name = "my-project", file = ".github/workflows/ci.yml")
```

---

### `pipeline_report(p, which_log = NA, file = NA, target = "ssh")`

Generates a structured execution report summarizing the status of pipeline nodes, execution durations, error logs, and warnings.

**Parameters:**

- `p` — The Pipeline to report on.
- `which_log` (optional) — Regex selector to report on a specific historical build log instead of the latest log.
- `file` (optional) — Target output file path. Defaults to `_pipeline/pipeline_report_<timestamp>.md` (ssh) or `.html` (web).
- `target` (optional) — Output format: `"ssh"` for Markdown format (default), or `"web"` for HTML format.

**Returns:**

String path to the generated report file.

**Examples:**
```t
pipeline_report(p)
pipeline_report(p, target = "web", file = "report.html")
```

---

### `set_pipeline_global_options(pipeline, functions = [:], include = [])`

Pure function that returns a new pipeline with the given defaults merged
into every node. The original pipeline is not modified.

**Parameters:**

- `pipeline` — The input pipeline (positional or piped).
- `functions` (optional) — Dict mapping runtime shorthands to function file paths.
  For example: `[rn: "functions.R", pyn: ["preproc.py", "utils.py"]]`.
  Each value can be a single path (String) or list of paths (List[String]).
  Runtime shorthands match node constructors: `rn` → R, `pyn` → Python, `jln` → Julia,
  `qn` → Quarto, `shn` → sh, `node` → T.
  Per-node `functions` arguments are appended after these global files.
- `include` (optional) — String or List[String]. File paths to include in every node's sandbox.
  Per-node `include` arguments are appended after these global includes.

**Returns:**

Pipeline — a new pipeline with the settings merged into every node.

**Examples:**
```t
p = pipeline {
  a = rn(<{ ... }>),
  b = pyn(<{ ... }>)
}
q = set_pipeline_global_options(p,
  functions = [rn: "functions.R"],
  include = "shared/config.yaml"
)
```

---



### `node(command, script = NA, runtime = "T", serializer = "default", deserializer = "default", env_vars = [:], args = [:], shell = NA, shell_args = [], functions = [], include = [], noop = false, flake = NA)`

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
- `flake` (optional) — A Nix flake reference (e.g. `github:b-rodrigues/tlang`, `path:../test_flake`) to use for this node's build environment. Each runtime component (t-lang binary, R packages, Julia path, nixpkgs) resolves independently from the custom flake when available, falling back to the project-level binding otherwise. **Project-level package declarations from `tproject.toml` (`[r-dependencies]`, `[py-dependencies]`, `[jl-dependencies]`) are still installed in per-node flake environments, built from the custom flake's nixpkgs.** Default: `NA` (use project flake).

**Returns:**

A pipeline node configuration object (`NodeDef`). Must be used as a named binding inside a `pipeline { ... }` block; the node code is executed by the pipeline builder, not immediately.

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

### `py(command, script = NA, serializer = "default", deserializer = "default", env_vars = [:], functions = [], include = [], noop = false, flake = NA)`

### `pyn(command, script = NA, serializer = "default", deserializer = "default", env_vars = [:], functions = [], include = [], noop = false, flake = NA)`

Configure a Python Pipeline Node. A convenience wrapper around `node()` with `runtime = "Python"`. Used directly within a `pipeline { ... }` block to execute Python code.

**Parameters:**


- `command` — The expression to evaluate inside the Python node (must be enclosed in `<{ ... }>` blocks).
- `serializer` (optional) — Custom serializer function. Default: `default`.
- `deserializer` (optional) — Custom deserializer function. Default: `default`.
- `env_vars` (optional) — Dictionary of environment variables to pass into the Nix sandbox.
- `functions` (optional) — Python files to source before execution.
- `include` (optional) — Additional files for the sandbox.
- `noop` (optional) — Whether to skip execution and generate a stub. Default: `false`.
- `flake` (optional) — A Nix flake reference (e.g. `github:b-rodrigues/tlang`, `path:../test_flake`) to use for this node's build environment. Each runtime component resolves independently from the custom flake when available, falling back to the project-level binding otherwise. Default: `NA` (use project flake).

**Returns:**

A pipeline node configuration object (`NodeDef`). Must be used as a named binding inside a `pipeline { ... }` block; the Python code is executed by the pipeline builder, not immediately.

---

### `rn(command, script = NA, serializer = "default", deserializer = "default", env_vars = [:], functions = [], include = [], noop = false, flake = NA)`

Configure an R Pipeline Node. A convenience wrapper around `node()` with `runtime = "R"`. Used directly within a `pipeline { ... }` block to execute R code.

**Parameters:**


- `command` — The expression to evaluate inside the R node (must be enclosed in `<{ ... }>` blocks).
- `serializer` (optional) — Custom serializer function. Default: `default`.
- `deserializer` (optional) — Custom deserializer function. Default: `default`.
- `env_vars` (optional) — Dictionary of environment variables to pass into the Nix sandbox.
- `functions` (optional) — R scripts to source before execution.
- `include` (optional) — Additional files for the sandbox.
- `noop` (optional) — Whether to skip execution and generate a stub. Default: `false`.
- `flake` (optional) — A Nix flake reference (e.g. `github:b-rodrigues/tlang`, `path:../test_flake`) to use for this node's build environment. Each runtime component resolves independently from the custom flake when available, falling back to the project-level binding otherwise. Default: `NA` (use project flake).

**Returns:**

A pipeline node configuration object (`NodeDef`). Must be used as a named binding inside a `pipeline { ... }` block; the R code is executed by the pipeline builder, not immediately.

---

### `jln(command, script = NA, serializer = "default", deserializer = "default", env_vars = [:], functions = [], include = [], noop = false, flake = NA)`

Configure a Julia Pipeline Node. A convenience wrapper around `node()` with `runtime = "Julia"`. Used directly within a `pipeline { ... }` block to execute Julia code.

**Parameters:**


- `command` — The expression to evaluate inside the Julia node (must be enclosed in `<{ ... }>` blocks).
- `script` — Path to an external `.jl` file to execute as the node body.
- `serializer` (optional) — Custom serializer symbol (e.g., `^csv`, `^json`, `^arrow`, `^onnx`). Default: runtime-native binary serialization (`jl_serialize`).
- `deserializer` (optional) — Custom deserializer symbol. Default: runtime-native binary deserialization.
- `env_vars` (optional) — Dictionary of environment variables to pass into the Nix sandbox.
- `functions` (optional) — Julia files to source before execution.
- `include` (optional) — Additional files for the sandbox.
- `noop` (optional) — Whether to skip execution and generate a stub. Default: `false`.
- `flake` (optional) — A Nix flake reference (e.g. `github:b-rodrigues/tlang`, `path:../test_flake`) to use for this node's build environment. Each runtime component resolves independently from the custom flake when available, falling back to the project-level binding otherwise. Default: `NA` (use project flake).

**Returns:**

A pipeline node configuration object (`NodeDef`). Must be used as a named binding inside a `pipeline { ... }` block; the Julia code is executed by the pipeline builder, not immediately.

---

### `qn(script = NA, serializer = "default", deserializer = "default", env_vars = [:], args = [:], functions = [], include = [], noop = false, flake = NA)`

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
- `flake` (optional) — A Nix flake reference (e.g. `github:b-rodrigues/tlang`, `path:../test_flake`) to use for this node's build environment. Each runtime component resolves independently from the custom flake when available, falling back to the project-level binding otherwise. Default: `NA` (use project flake).

**Returns:**

A pipeline node configuration object (`NodeDef`). Must be used as a named binding inside a `pipeline { ... }` block; the Quarto document is rendered by the pipeline builder, not immediately.

---

### `shn(command, script = NA, serializer = "text", deserializer = "default", env_vars = [:], args = [], shell = "sh", shell_args = [], functions = [], include = [], noop = false, flake = NA)`

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
- `flake` (optional) — A Nix flake reference (e.g. `github:b-rodrigues/tlang`, `path:../test_flake`) to use for this node's build environment. Each runtime component resolves independently from the custom flake when available, falling back to the project-level binding otherwise. Default: `NA` (use project flake).

**Returns:**

A pipeline node configuration object (`NodeDef`). Must be used as a named binding inside a `pipeline { ... }` block; the shell command is executed by the pipeline builder, not immediately.

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

### Pattern Functions (`map_pattern`, `cross_pattern`, `slice_pattern`, `head_pattern`, `tail_pattern`, `sample_pattern`)

Pattern functions are used as the `pattern` argument of `node()` inside a `pipeline { ... }` block. They declare that a node should be expanded into multiple branches — one per element or a Cartesian product of its dependencies.

**`map_pattern(dep1, dep2, ...)`** — Create one branch per element of each dependency. All dependencies must have the same length. Each branch receives the element at position `i` from every dependency.

**`cross_pattern(sub_pattern1, sub_pattern2, ...)`** — Cartesian product of sub-patterns. Each sub-pattern must be a `map_pattern(...)` call. Produces `len(s1) * len(s2) * ...` branches.

**`slice_pattern(dep, [i, j, ...])`** — Select specific indices from a dependency.

**`head_pattern(dep, n)`** — Take the first `n` elements.

**`tail_pattern(dep, n)`** — Take the last `n` elements.

**`sample_pattern(dep, n)`** — Randomly sample `n` elements.

**Note:** `slice_pattern`, `head_pattern`, `tail_pattern`, and `sample_pattern` are fully supported and expanded by `expand_pipeline`.

**Parameters:**

- `dep`, `dep1`, `dep2`, ... — Dependency names (symbols) referring to upstream pipeline nodes.
- `n` — A positive integer count.
- `[i, j, ...]` — A list of integer indices (0-based).

**Returns:**

A pattern object used internally by `node()`.

**Examples:**
```t
p = pipeline {
  x = [10, 20, 30]
  -- One branch per x value:
  y = node(command = <{ x * 2 }>, pattern = map_pattern(x))
}
expanded = expand_pipeline(p)
-- pipeline_nodes(expanded) == ["x", "y_branch_1", "y_branch_2", "y_branch_3"]

p2 = pipeline {
  a = [1, 2]
  b = [10, 20]
  -- 2 x 2 = 4 branches:
  c = node(command = <{ a + b }>, pattern = cross_pattern(map_pattern(a), map_pattern(b)))
}
expanded2 = expand_pipeline(p2)
-- pipeline_nodes(expanded2) == ["a", "b", "c_branch_1", "c_branch_2", "c_branch_3", "c_branch_4"]
```

**Note:** Non-T runtime branching is supported — see the advanced pipeline tutorial for serializer/deserializer requirements.

---

### `expand_pipeline(p, to_script = NA)`

Expand pattern-based branching in a pipeline. Patterned nodes (using `map_pattern`, `cross_pattern`, `slice_pattern`, `head_pattern`, `tail_pattern`, or `sample_pattern`) are replaced with branch copies.

**Parameters:**

- `p` — Pipeline object to expand.
- `to_script` (optional) — File path to write the expanded pipeline script as a T source file.

**Returns:**

A Pipeline with branches in place of patterned nodes. Branches are named `<original>_branch_<N>`.

**Examples:**
```t
p = pipeline {
  x = [1, 2, 3]
  y = node(command = <{ x }>, pattern = map_pattern(x))
}
expanded = expand_pipeline(p)
pipeline_nodes(expanded)  -- ["x", "y_branch_1", "y_branch_2", "y_branch_3"]

-- Write expanded pipeline to a file for inspection:
expand_pipeline(p, to_script = "expanded.t")
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

### `pipeline_run(pipeline, nix_options = NA)`

Re-execute a pipeline. If `nix_options` is provided, triggers a cache-aware Nix build of the pipeline using the specified options. Otherwise, re-executes the pipeline dynamically in-memory.

**Parameters:**

- `pipeline` — Pipeline object
- `nix_options` (optional) — Dict of Nix build options. Supported keys:
  - `targets` — String, List, or Vector of specific node names to build.
  - `force` — Bool, String, List, or Vector of specific nodes to force-rebuild.
  - `dry_run` — Bool. If true, returns a planned build actions DataFrame instead of building.
  - `max_jobs` — Positive Int. Limit parallel build jobs.
  - `cache` — String. Cachix cache name.
  - `builders` — String. Remote builder specification (SSH syntax).
  - `keep_env` — String, List, or Vector of environment variable names to pass into the sandbox.
  - `sandbox` — Bool or String (`"relaxed"`, `"strict"`, `"none"`). Sandbox policy.

**Returns:**

Pipeline object with updated values (or DataFrame if `dry_run = true`)

**Examples:**
```t
p = pipeline { x = 10; y = x * 2 }
p2 = pipeline_run(p)
df = pipeline_run(p, nix_options = [dry_run: true])
```

---

### `populate_pipeline(pipeline, build = false, verbose = 0, nix_options = NA)`

Prepare pipeline infrastructure in `_pipeline/`.

**Parameters:**

- `pipeline` — Pipeline object
- `build` (optional) — If true, triggers a Nix build of all nodes.
- `verbose` (optional) — Non-negative Int. Nix build verbosity level.
- `nix_options` (optional) — Dict of Nix build options. Supported keys:
  - `targets` — String, List, or Vector of specific node names to build.
  - `force` — Bool, String, List, or Vector of specific nodes to force-rebuild.
  - `dry_run` — Bool. If true, returns a planned build actions DataFrame instead of building.
  - `max_jobs` — Positive Int. Limit parallel build jobs.
  - `cache` — String. Cachix cache name.
  - `builders` — String. Remote builder specification (SSH syntax).
  - `keep_env` — String, List, or Vector of environment variable names to pass into the sandbox.
  - `sandbox` — Bool or String (`"relaxed"`, `"strict"`, `"none"`). Sandbox policy.

**Returns:**

Success message, BuildLog, or DataFrame.

**Examples:**
```t
populate_pipeline(p)
populate_pipeline(p, build = true)
populate_pipeline(p, build = true, nix_options = [max_jobs: 4, cache: "rstats-on-nix"])
```

---

### `build_pipeline(pipeline, verbose = 0, nix_options = NA, pipeline_name = NA)`

Shorthand for `populate_pipeline(p, build = true)`. Recommended for scripts run with `t run`.

**Parameters:**

- `pipeline` — Pipeline object
- `verbose` (optional) — Int build verbosity level. Defaults to `0` (quiet/minimalist live-status output without dumping failed node trace logs). Set `verbose = 1` or higher to print detailed node stdout/stderr failures directly to the terminal on build error.
- `pipeline_name` (optional) — String or Symbol. Records a human-readable name in the build log JSON (`"pipeline"` field) to help disambiguate logs in `list_logs()`.
- `nix_options` (optional) — Dict of Nix build options. Supported keys:
  - `targets` — String, List, or Vector of specific node names to build.
  - `force` — Bool, String, List, or Vector of specific nodes to force-rebuild.
  - `dry_run` — Bool. If true, returns a planned build actions DataFrame instead of building.
  - `max_jobs` — Positive Int. Limit parallel build jobs.
  - `cache` — String. Cachix cache name.
  - `builders` — String. Remote builder specification (SSH syntax).
  - `keep_env` — String, List, or Vector of environment variable names to pass into the sandbox.
  - `sandbox` — Bool or String (`"relaxed"`, `"strict"`, `"none"`). Sandbox policy.

**Returns:**

`BuildLog` with fields:
- `nodes` — per-node status/duration records
- `duration` — total build duration in seconds
- `failed_nodes` — list of failed/errored node names
- `out_path` — Nix output path for the build (migration path for previous string-return behavior)
(or `DataFrame` if `dry_run = true`)

**Examples:**
```t
build_pipeline(p)
build_pipeline(p, nix_options = [dry_run: true])
build_pipeline(p, nix_options = [targets: ["c"], max_jobs: 4, cache: "rstats-on-nix", force: ["c"]])
```

---

### `t_check(file, json = false, schema = false, env = false)`

REPL-callable version of `t check`. Runs structural, wire-phase, schema, environment, and **type annotation** checks on a T script and returns the diagnostics as a string. Type annotation checks compare `x: Int = expr` annotations against inferred types and emit `Warning` diagnostics for mismatches.

**Arguments:**

| Argument | Type | Default | Description |
|----------|------|---------|-------------|
| `file` | String | *(required)* | Path to the `.t` file to check |
| `json` | Bool | `false` | Output diagnostics as JSON |
| `schema` | Bool | `false` | Enable column-level schema validation |
| `env` | Bool | `false` | Enable `tproject.toml` environment checks |

**Returns:** `String` — formatted diagnostics (text or JSON, same as CLI `t check`).

**Examples:**

```t
result = t_check("src/pipeline.t")
result = t_check("src/pipeline.t", schema = true)
result = t_check("src/pipeline.t", json = true, schema = true, env = true)
```

---

### `t_diff(file, json = false, log_a = 2, log_b = 1)`

REPL-callable version of `t diff`. Compares two builds of a pipeline using per-node Nix content hashes and returns the diff summary as a string.

**Arguments:**

| Argument | Type | Default | Description |
|----------|------|---------|-------------|
| `file` | String | *(required)* | Path to the `.t` file to diff |
| `json` | Bool | `false` | Output diff as JSON |
| `log_a` | Int | `2` | Rank of the first (older) build log |
| `log_b` | Int | `1` | Rank of the second (newer) build log |

**Returns:** `String` — formatted diff (text or JSON, same as CLI `t diff`).

**Examples:**

```t
result = t_diff("src/pipeline.t")
result = t_diff("src/pipeline.t", log_a = 1, log_b = 2)
result = t_diff("src/pipeline.t", json = true)
```

---

### `t_fix(file, dry_run = false)`

REPL-callable version of `t fix`. Runs `t check --schema` on a file, extracts diagnostics with `suggested_fix`, and applies them mechanically. Supports `Rename_column` (replaces `$old` with `$new`) and `Add_node_arg` (inserts missing arguments into node definitions, e.g., adding a `deserializer` for cross-runtime dependencies).

**Arguments:**

| Argument | Type | Default | Description |
|----------|------|---------|-------------|
| `file` | String | *(required)* | Path to the `.t` file to fix |
| `dry_run` | Bool | `false` | Show what would be fixed without modifying the file |

**Returns:** `String` — summary of fixes applied (or would be applied), same as CLI `t fix`.

**Examples:**

```t
result = t_fix("src/pipeline.t")
result = t_fix("src/pipeline.t", dry_run = true)
```

---

### `t check` (CLI)

Structural pipeline validation without triggering Nix builds. Runs the full evaluator with `--failfast` but short-circuits Nix builds, so it can surface errors across all phases — syntax (parse), graph structure (wire), types (schema), and environment (missing files). The reported `tier` and `phase` reflect the deepest phase reached during evaluation, not a fixed depth limit.

**Usage:**

```bash
t check path/to/script.t              # human-readable output
t check --json path/to/script.t       # machine-readable JSON output
t check --schema path/to/script.t     # include column-level schema validation
t check --env path/to/script.t        # include environment resolution checks
t check --schema --env --json path/to/script.t  # combined: tier 1+2+3 in JSON
```

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | Wire-phase errors (cycles, missing deps, name errors) |
| 2 | Schema-phase errors (type mismatches) |
| 3 | Environment-phase errors (missing files, artifacts) |

**JSON output format (`--json`):**

```json
{
  "schema_version": "1",
  "status": "ok",
  "phase": "wire",
  "tier": 1,
  "diagnostics": []
}
```

The `tier` field is derived from the deepest phase that produced diagnostics: parse/wire errors yield `tier: 1`, schema errors yield `tier: 2`, and env/build/exec errors yield `tier: 3`. A clean run reports `"tier": 1` and `"phase": "wire"` as the default.

Each diagnostic entry contains: `id`, `error_class`, `severity`, `phase`, `node` (with nested `id`, `lang`, `file`, and `span` containing `start` and `end`), `message`, `expected`, `actual`, `caused_by`, and `suggested_fix`.

**`suggested_fix` structure:** When non-null, a `suggested_fix` is a JSON object with a `kind` field and fix-specific fields. Every fix also carries a `confidence` field (`"high"`, `"medium"`, or `"low"`) indicating whether the fix is deterministic or heuristic. Confidence is computed dynamically from diagnostic context (e.g., schema chain integrity, edit distance) rather than being a static label per fix kind:

| `kind` | Typical confidence | When it drops | Key fields |
|--------|-------------------|---------------|------------|
| `rename_column` | `"high"` | `"medium"` at edit distance 2; `"low"` at distance 3+ | `old_name`, `new_name`, `target_node` |
| `add_node_arg` | `"medium"` | Always `"medium"` | `node`, `arg`, `target_node` |
| `suggest_identifier` | varies | Scales with edit distance and uniqueness | `name`, `suggestion`, `target_node` |
| `run_command` | `"low"` | Always `"low"` | `command`, `description`, `target_node` |

**`error_class` enum values:** `structural_error`, `name_error`, `arity_error`, `type_error`, `parse_error`, `file_error`, `key_error`, `index_error`, `value_error`, `runtime_error`, `division_by_zero`, `assertion_error`, `match_error`, `shell_error`, `aggregation_error`, `na_predicate_error`, `missing_artifact`, `generic_error`, `schema_mismatch`, `missing_tproject`, `missing_package`, `missing_from_lockfile`, `nix_generation_error`, `nix_eval_error`, `na_warning`, `unknown_error`.

**Examples:**

```bash
# Check a pipeline script
t check analysis/pipeline.t

# Get JSON for editor integration
t check --json analysis/pipeline.t | jq '.diagnostics'
```

**How it works:**

`t check` runs the full evaluator with `--failfast` but skips Nix builds entirely. Pipeline construction (`build_pipeline`, `populate_pipeline`) is short-circuited, so the check completes instantly without requiring Nix or any runtime dependencies. Node bodies (R, Python, Julia, shell commands) are never evaluated — only the pipeline DAG structure is validated. This makes it suitable for pre-commit hooks, editor integration, and CI structural validation.

> **Note:** The `--env` flag additionally invokes `nix-instantiate --eval` and writes `pipeline.nix`/`dag.json` to `_pipeline/` (see below). If you need a tier-1-only check with zero side effects, use `t check` without `--env`.

**Schema validation (`--schema`):**

When `--schema` is passed, `t check` additionally runs static schema propagation on all pipelines found in the environment. For each pipeline, it:

1. Reads CSV headers from `read_csv(...)` calls to infer root node schemas.
2. Propagates schemas through the DAG via colcraft verbs (`select`, `mutate`, `summarize`, `filter`, `arrange`, etc.).
3. Checks all `$col` column references and formula variable references (`y ~ x`) against the inferred input schema at each node.

Schema errors are reported as `phase: "schema"` diagnostics and trigger exit code 2.

**Environment validation (`--env`):**

When `--env` is passed, `t check` additionally runs environment resolution checks on all pipelines found in the environment:

1. **Package declarations**: Checks that R/Python/Julia packages required by the pipeline are declared in `tproject.toml`.
2. **Lockfile consistency**: For `r_resolver = "renv"`, verifies that declared R packages exist in `renv.lock`.
3. **Nix evaluation**: Generates `pipeline.nix` and `dag.json` in `_pipeline/`, then runs `nix-instantiate --impure --eval --strict` to validate that the Nix expressions evaluate correctly. This writes to the project's pipeline directory as a side effect.

Environment errors are reported as `phase: "env"` diagnostics and trigger exit code 3.

**Watch mode (`--watch`):**

When `--watch` is passed, `t check` runs immediately, then polls the input file for changes (every 0.5s). On each modification, it re-runs the check and prints updated results. Press Ctrl+C to stop. Watch mode can be combined with `--schema` and/or `--env`.

---

### `t run` (CLI)

Executes a T source file. By default, `t run` prints human-readable output as the pipeline builds. With `--json`, it emits newline-delimited JSON (NDJSON) events to stdout — one JSON object per line — so agents can react to the first failing node without waiting for the entire DAG to finish.

**Usage:**

```bash
t run <file.t>              # human-readable output (default)
t run --json <file.t>       # streaming NDJSON events to stdout
t run <file.t> --json       # --json can also appear after the file
```

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | Pipeline completed successfully |
| 1 | Wire-phase error (missing deps, cycles) |
| 2 | Schema-phase error (type mismatch) |
| 3 | Environment/build error (Nix failure, missing runtime) |

Exit codes are the same whether `--json` is used or not.

**NDJSON event schema (`--json`):**

Each line is a self-contained JSON object with a common envelope:

```json
{
  "schema_version": "1.0",
  "seq": 1,
  "ts": "2026-07-10T14:32:01.123Z",
  "event": "run_started",
  ...
}
```

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | String | Always `"1.0"`. Reserved for future changes. |
| `seq` | Int | Monotonically increasing sequence number across the entire run. Starts at 1. |
| `ts` | String | ISO-8601 UTC timestamp of emission. |
| `event` | String | One of: `run_started`, `node_failed`, `node_skipped`, `run_finished`. |

**Event types:**

#### `run_started` (emitted once, first line)

Emitted before the first Nix build. Carries the full pipeline DAG so consumers can reason about root causes while the stream is still open.

```json
{
  "schema_version": "1.0",
  "seq": 1,
  "ts": "2026-07-10T14:32:01.123Z",
  "event": "run_started",
  "file": "pipeline.t",
  "nodes": [
    {"id": "a", "lang": "r"},
    {"id": "b", "lang": "python", "depends_on": ["a"]},
    {"id": "c", "lang": "r", "depends_on": ["b"]}
  ]
}
```

#### `node_failed` (emitted per failure)

Emitted when a node's Nix build fails. Includes the error message and the last 200 lines of the build log inline.

```json
{
  "schema_version": "1.0",
  "seq": 2,
  "ts": "2026-07-10T14:32:05.456Z",
  "event": "node_failed",
  "node": {"id": "b", "lang": "python"},
  "message": "Nix build failed for node 'b'",
  "log_tail": "...last 200 lines of build log..."
}
```

The `log_tail` field is a string containing the tail of `_pipeline/logs/<node>.log`. If the log is unavailable or empty, the field is an empty string.

#### `node_skipped` (emitted per skip)

Emitted when a downstream node is skipped because an upstream dependency failed. The `because` field names the first failed ancestor.

```json
{
  "schema_version": "1.0",
  "seq": 3,
  "ts": "2026-07-10T14:32:05.457Z",
  "event": "node_skipped",
  "node": {"id": "c", "lang": "r"},
  "because": "b"
}
```

#### `run_finished` (emitted once, last line)

Emitted after all nodes have been attempted. The `root_causes` array is authoritative here (computed from the full graph, not emitted on `node_failed` events). The `status` field is one of `"ok"`, `"failed"`, or `"skipped"`.

```json
{
  "schema_version": "1.0",
  "seq": 4,
  "ts": "2026-07-10T14:32:06.789Z",
  "event": "run_finished",
  "file": "pipeline.t",
  "status": "failed",
  "total_nodes": 3,
  "failed": 1,
  "skipped": 1,
  "root_causes": ["b"]
}
```

**Per-node build logs:**

During execution, each node's stderr is captured to `_pipeline/logs/<node>.log`. These logs persist after the run and can be inspected with `read_past_node(node, "build")` or `read_past_node(node, "run")`.

**Example: agent usage**

```bash
t run --json pipeline.t 2>/dev/null | while IFS= read -r line; do
  event=$(echo "$line" | jq -r '.event')
  if [ "$event" = "node_failed" ]; then
    node=$(echo "$line" | jq -r '.node.id')
    echo "FAILED: $node"
    echo "$line" | jq -r '.log_tail' | tail -5
    break
  fi
done
```

---

### `read_node(node)`

Read a dynamically evaluated or materialized artifact from an in-scope pipeline build.

**Parameters:**


- `node` — The ComputedNode to read (e.g. `p.node_name`)

**Returns:**

Deserialized value, wrapped with diagnostics.

**Examples:**
```t
read_node(p.summary_stats)
```

---

### `read_past_node(node, which_log)`

Read a pipeline node from a specific historical build log without the pipeline being in scope. The node argument is NSE-captured from `p.node_name` syntax.

**Parameters:**


- `node` — The node to read, written as `p.node_name` (captured before evaluation)
- `which_log` (required) — Regex pattern matching a specific build log filename

**Examples:**
```t
read_past_node(base_p.raw, which_log = "qcfs")
```

---

### `debug_node(node)`

Launches an interactive guest subshell (Python, R, or Julia REPL) to debug a pipeline node using its exact build state and context.

**Parameters:**

- `node` — The ComputedNode to debug (e.g. `p.node_name`).

**Returns:**

Runs interactively. Control returns to the parent T REPL once the subshell is exited.

**Details:**
Within the subshell, all upstream build paths and companion library loaders are provided, and custom project-level variables (`p_env_vars`/`un_env_vars`) are propagated directly. To enforce strict reproducibility and prevent configuration drift, all imperative package updates (e.g., `pip`, `install.packages`, `Pkg.add`) are dynamically intercepted and blocked.

**Examples:**
```t
p = pipeline { a = 1; b = a + 5 }
build_pipeline(p)
debug_node(p.b)
```

---

### `inspect_log(which_log = NA)`

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

### `build_log(p)`

Returns the `BuildLog` of the latest Nix build for the given pipeline. Contains detailed node-level status records, duration, failed node names, and `out_path`.

**Parameters:**

- `p` — The Pipeline object to retrieve the build log for.

**Returns:**

`BuildLog` — A structured build log record.

**Examples:**
```t
p = pipeline { a = 1 / 0 }
build_pipeline(p)
log = build_log(p)
```

---

### `build_log_to_frame(log)`

Tabulates a `BuildLog` record into a structured DataFrame summarizing the build status, duration, and Nix store paths of all pipeline nodes.

**Parameters:**

- `log` — The `BuildLog` record (retrieved via `build_log(p)`).

**Returns:**

`DataFrame` — A DataFrame with columns `name`, `status`, `duration`, and `path`.

**Examples:**
```t
log = build_log(p)
df = build_log_to_frame(log)
-- Returns a DataFrame:
--   name  | status     | duration | path
--   "a"   | "Errored"  | 0.02     | "/nix/store/..."
```

---

### `build_log_history(p, n = NA, pattern = NA)`

Returns a summary DataFrame of all historical builds matching the current pipeline's node signature, ordered from most recent to oldest.

**Parameters:**

- `p` — The Pipeline object.
- `n` (optional) — Positive Int. Maximum number of historical builds to return.
- `pattern` (optional) — String. Regular expression pattern to filter log filenames (e.g. `".*test.*"`).

**Returns:**

`DataFrame` — A DataFrame detailing historical builds with columns:
- `build_id` (1-indexed rank from most recent to oldest)
- `timestamp` (ISO-8601 UTC string of build time)
- `duration` (total duration in seconds)
- `n_nodes` (total number of nodes)
- `n_failed` (number of failed/errored nodes)
- `n_warnings` (number of warnings issued)
- `out_path` (Nix output store path for the build)
- `hash` (unique content hash of build input signature)

**Examples:**
```t
p = pipeline { a = 1; b = 2 }
hist = build_log_history(p, n = 5)
```

---

### `node_diff(node_a, node_b, log_a = "latest", log_b = "latest", key = [], context = 3)`

Compares the dynamic evaluations or built artifacts of `node_a` and `node_b` across two historical builds (defaults to comparing the latest build of both).

**Parameters:**

- `node_a` — The ComputedNode to compare.
- `node_b` — The second ComputedNode to compare.
- `log_a` (optional) — 1-indexed build rank (Int) or regular expression filename filter (String) or timestamp prefix for `node_a`. Default: `"latest"`.
- `log_b` (optional) — 1-indexed build rank (Int) or regular expression filename filter (String) or timestamp prefix for `node_b`. Default: `"latest"`.
- `key` (optional) — List of symbols representing natural key column(s) for DataFrame row alignment. Default: `[]`.
- `context` (optional) — Number of unchanged rows shown around each hunk for patient diffs. Default: `3`.

**Returns:**

`Dict` — A structured type-sensitive diff dictionary containing:
- **For DataFrames** (`csv`, `arrow`, `parquet`): `schema_changed` (Bool), `added_columns` (List), `removed_columns` (List), `nrows_a` (Int), `nrows_b` (Int), and `numeric_drift` (DataFrame summarizing column-level mean values and shift percentages).
- **For PMML Models** (`pmml`): `model_type` (String), `coefficients_changed` (Bool), and `coef_diff` (DataFrame comparing regression coefficients and intercept shift deltas). Falls back to generic structural equality diff for non-regression models.
- **For Text Files** (`text`): `changed` (Bool), `lines_added` (Int), `lines_removed` (Int), and `diff` (String unified diff output).
- **For Python-native artifacts** (for example pickled NumPy ndarrays): `kind = "python_object_diff"`, unified diff line counts, rendered git-like diff hunks, and shape/dtype metadata when available.
- **For Julia-native artifacts** (for example serialized arrays or structs): `kind = "julia_object_diff"`, DeepDiffs-rendered summaries, captured diff lines, and type/shape metadata when available.
- **For R-native artifacts** (for example serialized model objects): `kind = "r_object_diff"`, diffobj-rendered summaries, captured diff lines, and class/type metadata when available.
- **For Generic/Scalars**: `value_a` (Any), `value_b` (Any), `changed` (Bool), and `delta` (Float numeric difference or NA).

Native Python, Julia, and R object diffs are preserved only for artifacts using
the standard `default` or `tobj` serializers. Custom serializer names use the
normal artifact-loading path instead; use the companion helper package directly
when a native artifact requires a custom deserializer. Julia-native diffs are
executed through a fresh Julia helper process per comparison, so repeated large
diffs will include Julia startup cost.

**Examples:**
```t
p = pipeline { a = 1; b = 2 }
-- Compare most recent to second most recent
diff_scalar = node_diff(p.a, p.a)

-- Compare with explicit 1-indexed ranks or regex patterns
diff_model = node_diff(p.model_node, p.model_node, log_a = ".*train1.*", log_b = ".*train2.*")
```

---

### `diff_summary(p)`

Compares the two most recent builds of a pipeline and returns a DataFrame summarizing which nodes changed, were added, or were removed. Uses per-node Nix content hashes stored in build logs for fast comparison without loading artifacts.

**Parameters:**

- `p` — The pipeline to compare builds for.

**Returns:**

`DataFrame` — A summary with columns:
- `name` (String) — Node name.
- `status` (String) — One of `"unchanged"`, `"changed"`, `"added"`, `"removed"`.
- `hash_a` (String) — Nix content hash from build A.
- `hash_b` (String) — Nix content hash from build B.
- `class_a` (String) — Output value class from build A.
- `class_b` (String) — Output value class from build B.

**Examples:**
```t
p = pipeline { a = 1; b = 2 }
build_pipeline(p)
-- ... edit pipeline ...
build_pipeline(p)
summary = diff_summary(p)
print(summary)
```

---

### CLI: `t diff`

The `t diff` command provides the same functionality from the shell, without needing to write a T script:

```bash
t diff <file.t>                    # compare last two builds
t diff <file.t> --json             # structured JSON output
t diff <file.t> --log-a 2 --log-b 4  # compare specific build ranks
```

---

### CLI: `t fix`

Mechanically applies `suggested_fix` values from `t check --json` diagnostics. Runs `t check --json` internally, collects diagnostics with non-null `suggested_fix`, and applies them to the source file.

```bash
t fix <file.t>                     # apply all suggested fixes
t fix --dry-run <file.t>           # preview fixes without applying
```

**Supported fix types:**

| Fix Kind | Action |
|----------|--------|
| `rename_column` | Replaces all occurrences of the old column name with the new name |
| `add_node_arg` | (planned) Adds an argument to a pipeline node |
| `pin_package_version` | (planned) Adds or updates a package version in `tproject.toml` |

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | Fixes applied (or `--dry-run` preview completed) |
| 1 | No fixes available or `t check` failed |

**Example:**

```bash
$ t check --json pipeline.t | jq '.diagnostics[].suggested_fix'
{
  "kind": "rename_column",
  "old_name": "mpg",
  "new_name": "MPG",
  "target_node": "clean",
  "file": "pipeline.t",
  "line": 5,
  "confidence": "high"
}
```

---

### `t_test()`

REPL-callable version of `t test`. Runs the test suite and returns a DataFrame with structured results for programmatic inspection.

**Returns:** `DataFrame` — columns: `file` (String), `status` ("passed" or "failed"), `duration_ms` (Float), `error` (String or NA)

Note: `duration_ms` is a Float in the REPL DataFrame, but an integer in CLI `--json` output. Both represent milliseconds.

**Examples:**

```t
results = t_test()
-- DataFrame with columns: file, status, duration_ms, error

-- Filter to show only failed tests
failed = results |> filter($status == "failed")
nrow(failed)  -- 0 if all tests passed

-- Count passed tests
results |> filter($status == "passed") |> nrow()

-- Run only specific tests
results = t_test(only = ["arithmetic", "strings"])

-- Exclude slow tests
results = t_test(not = ["slow"])
```

---

### CLI: `t test`

Runs the test suite for the current project. Discovers test files (`test-*.t`, `test_*.t`, or `*_test.t`) recursively in the `tests/` directory.

```bash
t test                        # human-readable output
t test --json                 # structured JSON output (no preamble)
t test --format junit         # JUnit XML output for CI
t test --json tests/          # specify project directory
t test --only "stats"         # run only tests matching "stats"
t test --not "slow"           # skip tests matching "slow"
t test --only "stats" --not "anova"  # combine filters (OR semantics for --only)
t test --failfast             # stop on first failure
t test --list                 # list discovered tests without running
t test --timeout 30           # mark tests exceeding 30s as failed
t test --coverage             # generate Bisect_ppx coverage summary after tests
```

**Output formats:**

| Flag | Description |
|------|-------------|
| (default) | Human-readable output with ✓/✗ indicators |
| `--json` | Structured JSON output (shorthand for `--format json`) |
| `--format json` | Structured JSON output |
| `--format junit` | JUnit XML output for CI/CD pipelines |

**Filtering flags:**

| Flag | Description |
|------|-------------|
| `--only PATTERN` | Run only tests whose path contains PATTERN (case-insensitive). Multiple `--only` flags use OR semantics. |
| `--not PATTERN` | Skip tests whose path contains PATTERN (case-insensitive). Multiple `--not` flags use OR semantics. |

**Execution flags:**

| Flag | Description |
|------|-------------|
| `--failfast` | Stop running tests after the first failure. |
| `--list` | List discovered test files without running them. Respects `--only` and `--not` filters. |
| `--timeout SECONDS` | Mark any test exceeding SECONDS as failed. Does not interrupt execution — the test runs to completion but is reported as a timeout failure. |
| `--coverage` | Clean old `.coverage` files, run tests, then generate a Bisect_ppx coverage summary. Requires a coverage-instrumented build (`nix build .#t-coverage` or `dune build --instrument-with bisect_ppx`). |

**`.tignore` support:**

Create `tests/.tignore` to automatically exclude test files. One pattern per line, `#` comments, blank lines ignored. Patterns match against the relative path from `tests/`. Directory patterns (e.g. `legacy/`) match at any depth, similar to `.gitignore` semantics.

```
# tests/.tignore
slow_integration.t      # exact filename
*_benchmark.t           # glob pattern
legacy/                 # directory at any depth
```

**JUnit XML schema (when using `--format junit`):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="t test" tests="2" failures="1" time="0.123">
  <testsuite name="t test" tests="2" failures="1" time="0.123">
    <testcase name="tests/test_pass.t" time="0.050" />
    <testcase name="tests/test_fail.t" time="0.073">
      <failure message="Assertion failed" type="TestFailure">
        AssertionError: test failed
      </failure>
    </testcase>
  </testsuite>
</testsuites>
```

### Test Fixtures

T doesn't have a dedicated `before_each`/`after_each` fixture mechanism because
pipelines already provide the necessary isolation and composition. Use `chain()`
to share a setup pipeline across test nodes:

```t
-- tests/test_with_fixture.t
fixture = pipeline {
  data = node(
    command = read_csv("tests/data/mtcars.csv"),
    serializer = ^csv
  )
}

test_filter = pipeline {
  check = node(
    command = {
      result = data |> filter($mpg > 20)
      assert(nrow(result) > 0)
    },
    serializer = ^csv
  )
}

test_mutate = pipeline {
  check = node(
    command = {
      result = data |> mutate($kpg = $mpg * 1.609)
      assert("kpg" in colnames(result))
    },
    serializer = ^csv
  )
}

-- Wire fixture output into each test
combined = chain(fixture, parallel(test_filter, test_mutate))
build_pipeline(combined)
```

Each node runs in an isolated Nix sandbox. The `fixture` pipeline's `data` node
builds a dataframe (via `read_csv`), serializes it to CSV for cross-sandbox
transfer, and downstream test nodes receive it as a dataframe they can pipe
directly — no redundant `read_csv()` wrapper needed.

---

## Explain Package

Introspection and LLM tooling.

### `explain(value)`

Get detailed explanation of a value. 

For DataFrames, returns a compact summary by default showing `kind`, `nrow`, `ncol`, and a `hint`. Detailed fields (`schema`, `na_stats`, `example_rows`) are accessible via dot notation.

**Specialized support for `collect_exceptions(p)` DataFrames**:
If the input DataFrame is the diagnostics table returned by `collect_exceptions(p)` (detected via the columns `["node", "status", "code", "message"]`), `explain()` behaves as follows:
- **Single Exception**: If the DataFrame contains exactly one row, calling `explain()` directly maps to that specific exception, returning a dictionary with keys `kind`, `type` (`"Error"` or `"Warning"`), `error_code`/`warning_code`, `error_message`/`warning_message`, and `node`.
- **Multiple Exceptions**: If there are zero or multiple rows, `explain()` returns an overarching `exceptions_list` dictionary containing keys `kind`, `type`, `description`, `count`, and `exceptions` (a list of mapped explanation dictionaries for each diagnostic element).

For pipeline node results returned by `read_node(...)`, `explain()` now returns a top-level node wrapper with `kind`, `node_name`, `diagnostics`, and `contents`. The `contents` field is the explained payload stored in the node. In the REPL and CLI `t explain ...`, explain output is shown with a tree-style formatter for readability, but the runtime value remains a normal `Dict`.


**Parameters:**


- `value` — Any value

**Returns:**

Dict with introspection data

**Examples:**
```t
explain(42)
-- {`kind`: "value", `type`: "Int", `value`: 42}

explain(df)
-- {`kind`: "to_dataframe", `nrow`: 100, `ncol`: 5, `hint`: "Use explain(df).schema, ..."}

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

## Testcraft Package

Purpose: unit-testing primitives, inspired by R's `testthat`. `expect_*` comparisons return an `Expect` value (`Expect_pass`, `Expect_stop msg`, or `Expect_hold msg`) rather than raising directly, so results can be inspected, combined, or passed straight to `assert()`.

### Why `assert(expect_*(...))` instead of plain `assert(condition)`?

While a raw boolean expression like `assert(colnames(df) == ["a", "b", "c"])` works, it evaluates to a bare `Bool`. When it fails, `assert` can only report a generic `AssertionError: expression evaluated to false`, giving no details on which element or column differed.

By contrast, `expect_*` functions perform detailed element-wise and structural comparisons. When wrapped in `assert()`, they provide rich diagnostic feedback:

- **Detailed Diff Messages**: `assert(expect_colnames(df, ["a", "b", "c"]))` or `assert(expect_equal(colnames(df), ["a", "b", "c"]))` reports exact mismatched column names, row counts, index differences, or type mismatches.
- **First-Class Expect Values**: Return `Expect_pass`, `Expect_stop msg`, or `Expect_hold msg` (used when comparisons involve `NA`), allowing tests to inspect outcomes or handle missingness explicitly.
- **Domain-Specific Expectations**: Dedicated helpers for type checking (`expect_type`), error matching (`expect_error`), dataset dimensions (`expect_nrow`, `expect_colnames`), and pipeline DAG structures (`expect_pipeline`, `expect_nodes`, `expect_dependency`).

---

### `expect_equal(actual, expected, tolerance = 1e-9)`

Compare `actual` against `expected`, returning an `Expect` value.

**Parameters:**

- `actual` — The computed value to check
- `expected` — The value `actual` is expected to equal
- `tolerance` (optional, named) — Absolute tolerance used for Float comparisons (default `1e-9`)

**Returns:**

An `Expect` value: `Expect_pass` (values matched), `Expect_stop` (values differed), or `Expect_hold` (comparison involved NA)

**Comparison rules:**

- `Error` arguments always stop: `` `actual`/`expected` is an error: ... ``
- `NA` arguments always hold: `` `actual` is NA, cannot compare `actual` != `expected` ``
- `Int`/`Float` are compared with tolerance (cross-numeric promotes to `Float`); `Bool`, `String`, `Date`, `Datetime` compare directly
- `Factor` compares against a `String` or another `Factor` by resolved level
- `DataFrame`, `Vector`, `List`, and `Dict` are compared element-wise (Dict comparison is order-insensitive), reporting the location of the first difference (column/row, index, label, or key)
- Mismatched types always stop: `` `actual` (Int) != `expected` (String) ``

**Examples:**
```t
expect_equal(1, 1)                              -- Expect_pass
expect_equal(1, 2)                               -- Expect_stop("`1` != `2`")
expect_equal(0.1 + 0.2, 0.3, tolerance = 1e-9)   -- Expect_pass
expect_equal(NA, 1)                              -- Expect_hold
assert(expect_equal(1, 1))                       -- true
assert(expect_equal(1, 2))                       -- Error(AssertionError: `1` != `2`.)
```

---

### `expect_pass(x)`

Check whether an `Expect` value passed.

**Parameters:**

- `x` — An `Expect` value

**Returns:**

`true` if `x` is `Expect_pass`, `false` otherwise

**Examples:**
```t
expect_pass(expect_equal(1, 1))   -- true
expect_pass(expect_equal(1, 2))   -- false
```

---

### `expect_fail(x)`

Check whether an `Expect` value failed (stopped or held).

**Parameters:**

- `x` — An `Expect` value

**Returns:**

`true` if `x` is `Expect_stop` or `Expect_hold`, `false` otherwise

**Examples:**
```t
expect_fail(expect_equal(1, 2))   -- true
expect_fail(expect_equal(1, 1))   -- false
```

---

### `expect_msg(x)`

Get the diagnostic message from a failing `Expect` value.

**Parameters:**

- `x` — An `Expect` value

**Returns:**

The `Stop`/`Hold` message (String), or an error if `x` is `Expect_pass`

**Examples:**
```t
expect_msg(expect_equal(1, 2))   -- "`1` != `2`"
```

---

### `expect_lt(a, b)`

Pass if `a < b` (numeric only).

**Parameters:**
- `a`, `b` — Numeric values (Int or Float)

**Returns:**
An `Expect` value, `Expect_hold` on NA/Error, `Expect_stop` if not strictly less.

**Examples:**
```t
assert(expect_lt(1, 2))
assert(expect_lt(1.5, 2.5))
```

---

### `expect_lte(a, b)`

Pass if `a <= b` (numeric only).

### `expect_gt(a, b)`

Pass if `a > b` (numeric only).

### `expect_gte(a, b)`

Pass if `a >= b` (numeric only).

---

### `expect_true(x)`

Pass only if `x` is `VBool true`. For a looser truthiness check, use `expect_truthy`.

**Parameters:**
- `x` — Value to check

**Returns:**
`Expect_pass` only when `x` is `VBool true`; `Expect_hold` on NA; `Expect_stop` otherwise.

**Examples:**
```t
assert(expect_true(true))
```

---

### `expect_false(x)`

Pass only if `x` is `VBool false`. For a looser falsiness check, use `expect_falsy`.

---

### `expect_truthy(x)`

Pass if `x` is truthy per `is_truthy` (`1`, `"a"`, non-empty containers, etc.).

---

### `expect_falsy(x)`

Pass if `x` is falsy (`0`, `false`, `VNullNode`, etc.). NA still holds.

---

### `expect_type(x, type_name)`

Pass if `type_name(x)` matches the given `type_name` string.

**Parameters:**
- `x` — Value to inspect
- `type_name` (String) — Expected type name (e.g. `"Int"`, `"String"`, `"DataFrame"`)

**Examples:**
```t
assert(expect_type(42, "Int"))
assert(expect_type("hello", "String"))
```

---

### `expect_error(expr, class = "", message = "")`

Pass if `expr` is a `VError`. Optionally filter by error class or message pattern.

**Parameters:**
- `expr` — Any value (typically the result of calling `error(...)`)
- `class` (optional, named) — Expected error code string (e.g. `"TypeError"`, `"RuntimeError"`)
- `message` (optional, named) — Regex pattern to match against the error message

**Returns:**
`Expect_pass` if all checks pass; `Expect_stop` describing what didn't match.

**Examples:**
```t
assert(expect_error(error("boom")))
assert(expect_error(error("boom"), class = "RuntimeError"))
assert(expect_error(error("invalid"), message = "invalid"))
```

---

### `expect_length(x, n)`

Pass if the length/size/row-count of `x` equals `n`.

**Parameters:**
- `x` — A container (Vector, List, String, DataFrame, Dict)
- `n` (Int) — Expected length

**Examples:**
```t
assert(expect_length(1:5, 5))
assert(expect_length("hello", 5))
```

---

### `expect_nrow(df, n)`

Pass if DataFrame has exactly `n` rows.

**Parameters:**
- `df` — A DataFrame
- `n` (Int) — Expected row count

**Examples:**
```t
assert(expect_nrow(to_dataframe(col1 = 1:3), 3))
```

---

### `expect_ncol(df, n)`

Pass if DataFrame has exactly `n` columns.

**Examples:**
```t
assert(expect_ncol(to_dataframe(col1 = 1:3, col2 = 4:6), 2))
```

---

### `expect_colnames(df, names)`

Pass if DataFrame column names match the given list of strings exactly (order-sensitive).

**Parameters:**
- `df` — A DataFrame
- `names` — List or Vector of Strings

**Examples:**
```t
assert(expect_colnames(to_dataframe(col1 = 1:3, col2 = 4:6), ["col1", "col2"]))
```

---

### `expect_has_colnames(data, names)`

Pass if a DataFrame, Dict, or named List contains at least all of the expected column/field names. Order is not required, and additional columns are permitted.

**Parameters:**
- `data` — A DataFrame, Dict, or named List
- `names` — String, or List/Vector of Strings

**Examples:**
```t
assert(expect_has_colnames(df, ["id", "val"]))
assert(expect_has_colnames(df, "id"))
```

---

### `expect_unique(x)`

Pass if all elements in a Vector, List, or DataFrame are distinct. Returns `Expect_stop` detailing the location of duplicate values if any are found.

**Parameters:**
- `x` — A Vector, List, or DataFrame

**Examples:**
```t
assert(expect_unique([1, 2, 3, 4]))
assert(expect_unique(df.$id))
```

---

### `expect_fields(x, names)`

Pass if a Dict's keys or a named List's labels match the given list of strings exactly.

**Parameters:**
- `x` — A Dict or named List
- `names` — List or Vector of Strings

**Examples:**
```t
assert(expect_fields({"a": 1, "b": 2}, ["a", "b"]))
```

---

### `expect_in(x, values, tolerance = 1e-9)`

Pass if `x` (or every element of a Vector or List `x`) is present in `values`. Checks each element of collections individually.

**Parameters:**
- `x` — A scalar value, Vector, or List to look for
- `values` — A Vector or List of values to search in
- `tolerance` (optional, named) — Absolute tolerance used for Float comparisons (default `1e-9`)

**Examples:**
```t
assert(expect_in(3, 1:5))
assert(expect_in(0.1 + 0.2, [0.3], tolerance = 1e-9))
```

---

### `expect_no_na(actual, col = "")`

Pass if the actual value, Vector, List, or DataFrame (optional column) contains zero NA values.

**Parameters:**
- `actual` — Any value, Vector, List, or DataFrame to check
- `col` (optional) — String column name when checking a specific DataFrame column

**Examples:**
```t
assert(expect_no_na([1, 2, 3]))
assert(expect_no_na(df, "val"))
```

---

### `expect_between(actual, min, max)`

Pass if the numeric value or vector elements fall inside the closed range `[min, max]`.

**Parameters:**
- `actual` — Int, Float, or Vector to check
- `min` — Numeric lower bound (inclusive)
- `max` — Numeric upper bound (inclusive)

**Examples:**
```t
assert(expect_between(25.0, 10.0, 50.0))
```

---

### `expect_match(actual, pattern)`

Pass if the actual String matches the given regular expression pattern.

**Parameters:**
- `actual` — String value to inspect
- `pattern` — Regular expression pattern string

**Examples:**
```t
assert(expect_match("user@example.com", ".*@.*"))
```

---

### `expect_str_contains(actual, substring)`

Pass if the actual String contains the specified substring.

**Parameters:**
- `actual` — String value to inspect
- `substring` — Substring to search for

**Examples:**
```t
assert(expect_str_contains("hello world", "world"))
```

---

### `expect_set_equal(list1, list2)`

Pass if two Lists or Vectors contain the exact same unique elements regardless of order.

**Parameters:**
- `list1` — First List or Vector
- `list2` — Second List or Vector

**Examples:**
```t
assert(expect_set_equal([1, 2, 3], [3, 2, 1]))
```

---

### `expect_empty(actual)`

Pass if a List, Dict, Vector, String, or DataFrame is empty (0 elements/rows/length).

**Parameters:**
- `actual` — List, Dict, Vector, String, or DataFrame

**Examples:**
```t
assert(expect_empty([]))
```

---

### `expect_summary(checks)`

Summarize a List or Dict of `Expect` values / check results into a DataFrame report table.

**Parameters:**
- `checks` — Dict or List of expectation check results

**Examples:**
```t
summary_df = expect_summary([c1: expect_equal(1, 1), c2: expect_equal(2, 2)])
```

### `expect_warning(node, kind = "", message = "")`

Pass if the given pipeline node produced at least one warning during execution.
Optionally filter by warning `kind` string (exact match) or `message` regex pattern.

**Parameters:**
- `node` — A `NodeResult` or `ComputedNode` value (obtained from `read_node()` or a pipeline result)
- `kind` (optional, named) — Exact warning kind to match (e.g. `"NAExcluded"`)
- `message` (optional, named) — Regex pattern to match against the warning message

**Examples:**
```t
assert(expect_warning(read_node(p.my_node)))
assert(expect_warning(read_node(p.my_node), kind = "NAExcluded"))
assert(expect_warning(read_node(p.my_node), message = "excluded"))
```

### `expect_pipeline(x)`

Pass if the given value `x` is a `Pipeline` value.

**Parameters:**
- `x` — The value to inspect.

**Examples:**
```t
assert(expect_pipeline(p))
```

### `expect_nodes(p, expected_names)`

Pass if the pipeline contains exactly the expected node names (including dynamic branch nodes).

**Parameters:**
- `p` — The pipeline to check.
- `expected_names` — List or Vector of expected node names.

**Examples:**
```t
assert(expect_nodes(p, ["load", "clean", "model"]))
```

### `expect_dependency(p, from_node, to_node)`

Pass if `to_node` directly or transitively depends on `from_node` in the pipeline DAG.

**Parameters:**
- `p` — The pipeline to check.
- `from_node` — The upstream node name (String).
- `to_node` — The downstream node name (String).

**Examples:**
```t
assert(expect_dependency(p, "load", "model"))
```

### `expect_has_pattern(p, node_name)`

Pass if `node_name` is defined with a dynamic branching pattern (e.g. mapping or crossing).

**Parameters:**
- `p` — The pipeline to check.
- `node_name` — The node name to inspect.

**Examples:**
```t
assert(expect_has_pattern(p, "train_model"))
```

### `expect_runtime(p, node_name, expected)`

Pass if `node_name` runtime matches the expected runtime name (e.g. `"R"`, `"Python"`, `"T"`, `"sh"`).

**Parameters:**
- `p` — The pipeline to check.
- `node_name` — The node name.
- `expected` — Expected runtime (String).

**Examples:**
```t
assert(expect_runtime(p, "model", "Python"))
```

### `expect_serializer(p, node_name, expected)`

Pass if `node_name` serializer matches the expected serializer.

**Parameters:**
- `p` — The pipeline to check.
- `node_name` — The node name.
- `expected` — Expected serializer (String or Symbol, e.g. `^arrow`, `^csv`).

**Examples:**
```t
assert(expect_serializer(p, "data", ^csv))
```

### `expect_deserializer(p, node_name, expected)`

Pass if `node_name` deserializer matches the expected deserializer.

**Parameters:**
- `p` — The pipeline to check.
- `node_name` — The node name.
- `expected` — Expected deserializer (String or Symbol).

**Examples:**
```t
assert(expect_deserializer(p, "model", ^onnx))
```

### `expect_noop(p, node_name, expected_noop)`

Pass if `node_name` noop flag matches the expected boolean value.

**Parameters:**
- `p` — The pipeline to check.
- `node_name` — The node name.
- `expected_noop` — Expected noop boolean value.

**Examples:**
```t
assert(expect_noop(p, "heavy_job", true))
```

### `expect_computed(node)`

Pass if the node is computed and has a finished value.

**Parameters:**
- `node` — A `ComputedNode` or `NodeResult` to check.

**Examples:**
```t
assert(expect_computed(res.heavy_job))
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
| `Expect` | `expect_equal(a, b)` | Result of a testcraft comparison (pass/stop/hold) |

---

## Next Steps

Now that you've explored the API, learn how to build reproducible data pipelines:

1. **[Pipeline Tutorial](pipeline_tutorial.md)** — Master T's core execution model.
2. **[Data Manipulation Examples](data_manipulation_examples.md)** — Practical examples of data wrangling.
3. **[Project Development](project_development.md)** — Master T's project structure and dependency management.
4. **[Package Development](package_development.md)** — Create reusable T libraries.
