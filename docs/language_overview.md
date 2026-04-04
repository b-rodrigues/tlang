# T Language Overview

> **Version**: 0.51.2

T is a functional programming language designed for declarative, tabular data manipulation. It combines the pipeline-driven style of R's tidyverse with OCaml's type discipline, producing a small, focused language for data wrangling and basic statistics.

---

## Quick Syntax Tour

```t
-- Variable assignment
x = 10
name = "Alice"

-- Variable re-assignment (Shadowing)
x := 20

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

-- Import specific names from a package or another .t file
import mypackage [fn1, fn2]
import "helpers.t" [clean_data, normalize]

-- Sequence generation
seq(5)                -- [1, 2, 3, 4, 5]
seq(1, 10, by = 2)    -- [1, 3, 5, 7, 9]
```

---

## Core Concepts

### Values and Types

T supports the following value types:

| Type        | Example                  | Description                        |
|-------------|--------------------------|-------------------------------------|
| `Int`       | `42`                     | Integer numbers                     |
| `Float`     | `3.14`                   | Floating-point numbers              |
| `Bool`      | `true`, `false`          | Boolean values                      |
| `String`    | `"hello"`                | Text strings                        |
| `List`      | `[1, 2, 3]`             | Ordered, heterogeneous collections  |
| `Dict`      | `{x: 1, y: 2}`          | Key-value maps with string keys     |
| `Vector`    | Column data              | Typed arrays (from DataFrames)      |
| `DataFrame` | `read_csv("data.csv")`   | Tabular data (rows × columns)       |
| `Pipeline`  | `pipeline { ... }`       | DAG-based execution graph           |
| `Function`  | `\(x) x + 1`            | First-class functions               |
| `NA`        | `NA`                     | Explicit missing value              |
| `Error`     | `error("msg")`           | Structured error value              |
| `NA`      | `NA`                   | Absence of value                    |
| `Symbol`    | `$mpg`                   | Name reference (NSE, DataFrames)    |
| `Expression`| `expr(1 + 2)`            | Captured code (for metaprogramming) |
| `Intent`    | `intent { ... }`         | LLM-friendly metadata block         |

### Variables and Assignment

```t
x = 42
name = "Alice"
active = true
```

Variables are bound with `=`. All values are immutable by default. To overwrite an existing binding (shadowing), use the `:=` operator:

```t
x = 10
x := 20    -- Overwrites x with 20
```

To remove a variable from the environment entirely, use the `rm()` function. It supports bare symbols, strings, and the `list` parameter:

```t
rm(x)             -- Removes x from the environment
rm("name")        -- Removes name by string
rm(a, b, c)       -- Removes multiple variables

vars = ["x", "y"]
rm(list = vars)   -- Removes variables 'x' and 'y'
```

### Arithmetic and Operators

```t
2 + 3       -- 5
10 - 3      -- 7
4 * 5       -- 20
15 / 3      -- 5
1 + 2.5     -- 3.5 (mixed int/float is promoted)

-- String concatenation is NOT supported with +
-- Use str_join() or paste() instead:
str_join(["hi", " T"], sep = "") -- "hi T"
```

Operator precedence follows standard mathematical conventions. Parentheses override precedence.

### Comparisons

```t
5 == 5    -- true
5 != 3    -- true
3 < 5     -- true
5 > 3     -- true
5 >= 5    -- true
2 <= 2    -- true
```

### Boolean Logic

```t
true and true   -- true
true and false  -- false
false or true   -- true
not true        -- false
```

---

## Tooling

### REPL

The T REPL (`dune exec src/repl.exe`) supports:

- **Readline editing** with arrow keys and history navigation
- **Persistent history** in `~/.t_history`
- **Multi-line input** for open brackets, parentheses, and braces
- **Magic commands** such as `:help`, `:quit`, and `:clear`
- **Signal-safe interrupts** so `Ctrl+C` returns you to the prompt cleanly

### Language Server Protocol (LSP)

T ships a native LSP server (`t-lsp`) for editor integrations such as VS Code:

- **Completion** for symbols, functions, and DataFrame columns
- **Go to definition** for bindings
- **Hover documentation** sourced from `--#` docstrings
- **Diagnostics** for parse and type errors

---

## Functions

### Lambda Syntax

T supports two equivalent function definition syntaxes:

```t
-- R-style lambda (preferred)
square = \(x) x * x

-- function keyword
square = function(x) x * x
```

### Multi-Argument Functions

```t
add = \(a, b) a + b
add(3, 7)  -- 10
```

### Closures

Functions capture their enclosing environment:

```t
make_adder = \(n) \(x) x + n
add5 = make_adder(5)
add5(10)  -- 15
```

### Higher-Order Functions

```t
numbers = [1, 2, 3, 4, 5]
map(numbers, \(x) x * x)     -- [1, 4, 9, 16, 25]
filter(numbers, \(x) x > 3)  -- [4, 5]
```

---

## Pipe Operators

T provides two pipe operators with different error-handling semantics.

### Conditional Pipe (`|>`)

The standard pipe `|>` passes the left-hand value as the first argument to the right-hand function. If the left-hand value is an error, the pipeline **short-circuits** and the error is returned immediately without calling the function:

```t
5 |> \(x) x * 2           -- 10
5 |> add(3)                -- 8 (equivalent to add(5, 3))
[1, 2, 3] |> map(\(x) x * x) |> sum  -- 14

-- Short-circuits on error:
error("boom") |> double    -- Error(GenericError: "boom")
```

Pipes work across lines for readability:

```t
[1, 2, 3, 4, 5]
  |> map(\(x) x * x)
  |> sum                   -- 55
```

### Maybe-Pipe (`?|>`)

The maybe-pipe `?|>` **always** forwards the left-hand value to the right-hand function, even if it is an error. This enables explicit error recovery patterns:

```t
-- Forward normal values (same as |>):
5 ?|> double               -- 10

-- Forward errors to recovery functions:
handle = \(x) if (is_error(x)) "recovered" else x
error("boom") ?|> handle   -- "recovered"

-- Chain recovery with normal processing:
recovery = \(x) if (is_error(x)) 0 else x
increment = \(x) x + 1
error("fail") ?|> recovery |> increment  -- 1
```

The maybe-pipe also works across lines:

```t
error("fail")
  ?|> recovery
  |> increment             -- 1
```

### When to Use Each Pipe

| Operator | On Error            | Use Case                        |
|----------|---------------------|---------------------------------|
| `\|>`    | Short-circuits      | Normal data pipelines           |
| `?\|>`   | Forwards to function| Error recovery, fallback values |

---

## Conditionals

```t
result = if (5 > 3) "yes" else "no"   -- "yes"
```

Conditionals are expressions — they return values.

---

## Pattern Matching (New)

T now supports pattern matching on lists and errors using the `match` expression. This addition provides a more declarative way to destructure data and handle error states.

```t
-- Matching on lists
x = [1, 2, 3]
result = match(x) {
  [h, ..t] => h,
  [] => 0
} -- 1

-- Matching on errors
res = 1 / 0
msg = match(res) {
  Error { msg: m } => m,
  _ => "not an error"
} -- "Division by zero"
```

Match arms are checked in order. If no patterns match, a `MatchError` is returned. Pattern bindings are scoped to the selected arm and do not leak out.

### Data Science Examples

Pattern matching is particularly useful for robust data pipelines and statistical reporting:

```t
-- 1. Graceful fallback for data loading
df = read_csv("data.csv")
data = match(df) {
  Error { msg } => {
    print(str_sprintf("Warning: %s. Falling back to backup.", msg));
    read_csv("backup.csv")
  },
  _ => df
}

-- 2. Destructuring calculation results
stats = [mean(x), sd(x), length(x)]
report = match(stats) {
  [m, s, n] => str_sprintf("Average: %f (±%f) from %d samples", m, s, n),
  _ => "Invalid statistics list"
}

-- 3. Handling pipeline validation
p = my_pipeline
status = match(pipeline_validate(p)) {
  [] => "Pipeline is valid and ready to build.",
  [first_err, ..others] => 
    str_join(["Found ", str_string(length(others) + 1), " validation errors."])
}
```

### Integration with Maybe-Pipe and First-Class Errors

Pattern matching is the final piece of T's "Errors-as-Values" philosophy. While the **maybe-pipe** (`?|>`) is used for simple forwarding and recovery, `match` provides precise control over different types of outcomes.

```t
-- Comprehensive error recovery pattern
read_csv("raw_data.csv")
  ?|> \(v) match(v) {
    Error { msg: m } => 
      if (str_detect(m, "File not found")) read_csv("default.csv")
      else error("DataLoadError", str_sprintf("Critical failure: %s", m)),

    df => df |> clean_data()
  }
```

#### Comparison of Error Handling Patterns

| Pattern | Behavior | Best Used For... |
|---------|----------|-----------------|
| `\|>` (Pipe) | Short-circuits on error | Standard "Happy Path" data flows. |
| `?\|>` (Maybe-Pipe) | Forwards errors to functions | Simple fallback values or generic logging. |
| `match` | Explicit branching | Complex recovery, destructuring messages, or handling multiple success/failure states. |

For error handling, `match` expressions automatically propagate unhandled errors. If the scrutinee is an `Error` and no pattern explicitly handles it (via `Error { ... }` or a catch-all `_`), the original error value is returned.

---

## Collections

### Lists

```t
numbers = [1, 2, 3]
length(numbers)  -- 3
head(numbers)    -- 1
tail(numbers)    -- [2, 3]
```

### Named Lists

```t
person = [name: "Alice", age: 30]
person.name  -- "Alice"
person.age   -- 30
```

### Dictionaries

```t
config = {host: "localhost", port: 8080}
config.host  -- "localhost"
config.port  -- 8080
```

### Symbols (`$`)

Symbols are name references that are not immediately evaluated. They are primarily used to reference DataFrame columns in verbs like `select($mpg)` or `filter($cyl > 4)`.

Symbols are created by prefixing an identifier with `$`:
```t
s = $my_symbol
type(s)  -- "Symbol"
```

---

## Missing Values (NA)

T uses explicit `NA` values with type tags. NA does **not** propagate implicitly — operations on NA produce errors:

```t
NA             -- untyped NA
na_int()       -- typed NA (Int)
na_float()     -- typed NA (Float)
na_bool()      -- typed NA (Bool)
na_string()    -- typed NA (String)

is_na(NA)      -- true
is_na(42)      -- false

-- NA does not propagate
NA + 1         -- Error(TypeError: "Operation on NA...")
```

### NA Handling in Aggregation Functions

By default, aggregation functions **error** when they encounter NA values. This forces you to handle missingness explicitly rather than silently ignoring it:

```t
mean([1, 2, NA, 4])           -- Error: NA encountered
sum([1, NA, 3])               -- Error: NA encountered
sd([1, NA, 3])                -- Error: NA encountered
quantile([1, NA, 3], 0.5)     -- Error: NA encountered
cor([1, NA, 3], [4, 5, 6])    -- Error: NA encountered
```

To compute statistics while skipping NA values, use `na_rm = true`:

```t
mean([1, 2, NA, 4], na_rm = true)           -- 2.33333333333
sum([1, NA, 3], na_rm = true)               -- 4
sd([2, 4, NA, 9], na_rm = true)             -- 3.60555127546
quantile([1, NA, 3, NA, 5], 0.5, na_rm = true) -- 3.
cor([1, NA, 3, 4], [2, 4, NA, 8], na_rm = true) -- 1. (pairwise deletion)
```

When all values are NA and `na_rm = true`, functions return `NA(Float)`:

```t
mean([NA, NA, NA], na_rm = true)    -- NA(Float)
sum([NA, NA, NA], na_rm = true)     -- 0
sd([NA, NA, NA], na_rm = true)      -- NA(Float)
```

---

## Error Handling

Errors are values, not exceptions. Failed operations return structured `Error` values:

```t
result = 1 / 0
is_error(result)     -- true
error_code(result)   -- "DivisionByZero"
error_message(result) -- "Division by zero"

-- Custom errors
err = error("something broke")
err = error("ValueError", "invalid input")
```

### Actionable Error Messages

T provides helpful error messages with suggestions:

```t
-- Name suggestions for typos (Levenshtein distance):
prnt(42)           -- Error(NameError: "'prnt' is not defined. Did you mean 'print'?")
slect(df, "name")  -- Error(NameError: "'slect' is not defined. Did you mean 'select'?")

-- Type conversion hints:
1 + true           -- Error(TypeError: "Cannot add Int and Bool. Hint: ...")
[1, 2] + 3         -- Error(TypeError: "Cannot add List and Int. Hint: Use map()...")

-- Function signature in arity errors:
f = \(a, b) a + b
f(1)               -- Error(ArityError: "Expected 2 arguments (a, b) but got 1")
```

### Assert

```t
assert(2 + 2 == 4)                -- true
assert(false, "custom message")   -- Error(AssertionError: ...)
```

---

## DataFrames

DataFrames are T's first-class tabular data type, loaded from CSV:

```t
df = read_csv("data.csv")
nrow(df)      -- number of rows
ncol(df)      -- number of columns
colnames(df)  -- list of column names
df.age        -- column as Vector

-- Optional arguments
df = read_csv("data.tsv", separator = ";")              -- custom separator
df = read_csv("data.csv", skip_lines = 2)          -- skip first N lines
df = read_csv("raw.csv", skip_header = true)        -- no header row
df = read_csv("messy.csv", clean_colnames = true)   -- normalize column names

-- Save DataFrames
write_csv(df, "output.csv")                         -- write to CSV
write_csv(df, "output.tsv", separator = "\t")             -- custom separator
```

### Column Name Cleaning

When `clean_colnames = true`, column names are normalized into safe, consistent snake_case identifiers:

```t
-- Original headers: "Growth%", "MILLION€", "café"
df = read_csv("data.csv", clean_colnames = true)
colnames(df)  -- ["growth_percent", "million_euro", "cafe"]

-- Standalone function on an existing DataFrame
df2 = clean_colnames(df)

-- Or on a list of strings
clean_colnames(["A.1", "A-1"])  -- ["a_1", "a_1_2"]
```

The cleaning pipeline applies these transformations in order:

| Stage | Transformation | Example |
|-------|---------------|---------|
| 1 | Symbol expansion (`%` → `percent`, `€` → `euro`, `$` → `dollar`, `£` → `pound`, `¥` → `yen`) | `"growth%"` → `"growthpercent"` |
| 2 | Diacritics stripping | `"café"` → `"cafe"` |
| 3 | Lowercase | `"MyCol"` → `"mycol"` |
| 4 | Non-alphanumeric → `_`, collapse runs, trim edges | `"foo---bar"` → `"foo_bar"` |
| 5 | Prefix digit-leading names with `x_` | `"1st"` → `"x_1st"` |
| 6 | Empty names → `col_N` | `""` → `"col_1"` |
| 7 | Collision resolution (first unchanged, then `_2`, `_3`, …) | `["A.1", "A-1"]` → `["a_1", "a_1_2"]` |

The transformation is pure, stable across platforms, and idempotent.

### Data Manipulation

T provides six core data verbs with dollar-prefix NSE syntax for concise column references:

```t
-- Use $column for column references
df |> select($name, $age)
df |> filter($age > 25)
df |> mutate($age_plus_10 = $age + 10)         -- named-arg style
df |> arrange($age, "desc")
df |> 
  group_by($dept) |> 
  summarize($count = nrow($dept))           
-- named-arg style
df |> 
  group_by($dept) |> 
  mutate($dept_size, \(g) nrow(g))
```

#### Named-Arg Syntax (`$col = expr`)

For `mutate` and `summarize`, you can use `$col = expr` to name the result column and provide an NSE expression in one step:

```t
-- mutate: $new_col = NSE expression (auto-wrapped in lambda per row)
df |> mutate($bonus = $salary * 0.1)
df |> mutate($full_name = $first + " " + $last)

-- summarize: $result_col = NSE aggregation (auto-wrapped in lambda per group)
df |> group_by($dept)
   |> summarize($avg_salary = mean($salary), $count = nrow($dept))
```

#### Dollar-Prefix vs Dot Accessor

- **Dollar (`$`)**: Column reference in DataFrame context — `$column_name`
- **Dot (`.`)**: Field access on an explicit object — `row.field`, `obj.property`

```t
-- Dollar: references columns contextually (no explicit row variable)
df |> filter($age > 30)

-- Dot: accesses fields on an explicit object (in lambda context)
df |> filter($age > 30)
```

### Window Functions

Window functions compute values across a set of rows without collapsing them. All window functions handle `NA` gracefully.

#### Ranking Functions

Ranking functions assign ranks to elements. NA values receive NA rank; ranks are computed only among non-NA values:

```t
row_number([10, 30, 20])    -- Vector[1, 3, 2]   (ties broken by position)
min_rank([1, 1, 2, 2, 2])  -- Vector[1, 1, 3, 3, 3]  (gaps after ties)
dense_rank([1, 1, 2, 2])   -- Vector[1, 1, 2, 2]     (no gaps)
cume_dist([1, 2, 3])        -- Vector[0.333..., 0.666..., 1.0]
percent_rank([1, 2, 3])     -- Vector[0.0, 0.5, 1.0]
ntile([1, 2, 3, 4], 2)     -- Vector[1, 1, 2, 2]

-- NA handling: NA positions get NA rank
row_number([3, NA, 1])     -- Vector[2, NA, 1]
min_rank([3, NA, 1, 3])   -- Vector[2, NA, 1, 2]
```

#### Offset Functions (lag/lead)

Shift values forward or backward, filling with NA. NA values in the input pass through:

```t
lag([1, 2, 3, 4])          -- Vector[NA, 1, 2, 3]
lag([1, 2, 3, 4], 2)       -- Vector[NA, NA, 1, 2]
lead([1, 2, 3, 4])         -- Vector[2, 3, 4, NA]
lead([1, 2, 3, 4], 2)      -- Vector[3, 4, NA, NA]

-- NA passes through
lag([1, NA, 3])            -- Vector[NA, 1, NA]
```

#### Cumulative Functions

Cumulative functions propagate NA: once NA is encountered, all subsequent values become NA (matching R behavior):

```t
cumsum([1, 2, 3, 4])      -- Vector[1, 3, 6, 10]
cummin([3, 1, 4, 1])      -- Vector[3, 1, 1, 1]
cummax([1, 3, 2, 5])      -- Vector[1, 3, 3, 5]
cummean([2, 4, 6])         -- Vector[2.0, 3.0, 4.0]
cumall([true, true, false]) -- Vector[true, true, false]
cumany([false, true, false]) -- Vector[false, true, true]

-- NA propagation
cumsum([1, NA, 3])         -- Vector[1, NA, NA]
```

---

## Shell Escape (`?<{ }>`)

The shell escape syntax allows you to execute arbitrary shell commands directly from within T. This is useful for interacting with the filesystem, running git commands, or using other CLI tools.

### As a Statement

When used as a standalone statement, the command is executed and its output is printed directly to `stdout`. The return value of the expression is `NA`.

```t
?<{ls -la}>
?<{git status}>
```

### As an Expression

When used as part of an expression (e.g., in an assignment), the shell command's `stdout` is captured and returned as a `String`.

```t
files = ?<{ls}>
current_user = ?<{whoami}>
```

### Special Case: `cd`

The `cd` command is special-cased to change the working directory of the T interpreter itself, rather than just a sub-shell.

```t
?<{cd /tmp}>
?<{pwd}>       -- will show /tmp
?<{cd ~}>      -- expands ~ correctly
```

### Multiline Commands

Shell escapes support multiline commands. Indentation common to all non-empty lines is automatically stripped.

```t
?<{
  git add .
  git commit -m "update"
  git push
}>
```

### Error Handling

If a shell command fails (returns a non-zero exit code), it produces a `ShellError` containing the `stderr` output.

```t
result = ?<{ls /nonexistent}>
is_error(result)  -- true
```

---

## Pipelines

Pipelines define named computation nodes with automatic dependency resolution and provide the foundation for reproducible, polyglot workflows. You can see a complete, polyglot version of this example in the [`examples/polyglot_pipeline.t`](../examples/polyglot_pipeline.t) file.

Built-in serializer keywords include `"csv"`, `"arrow"`, `"pmml"`, and `"onnx"` (or `^csv`, `^arrow`, `^pmml`, `^onnx` when referencing the first-class serializer values directly).

The **ONNX** system provides full cross-runtime model portability:
- **`^onnx` Serializer**: Automatically handles model export/import between R, Python, and T nodes.
- **Native Inference**: Use `t_read_onnx()` to load models and `predict()` for high-performance scoring directly inside T nodes, with no dependency on R or Python at prediction time.
- **Rich Metadata**: T-native ONNX objects contain input/output schema and custom model properties (producer, description, feature names) extracted directly from the session.

```t
p = pipeline {
  -- 1. Load data natively in T (CSV backend)
  data = node(
    command = read_csv("examples/sample_data.csv") |> filter($age > 25),
    serializer = "csv"
  )
  
  -- 2. Train a statistical model in R (using the rn() wrapper)
  model_r = rn(
    command = <{ lm(score ~ age, data = data) }>,
    serializer = "pmml",
    deserializer = "csv"
  )
  
  -- 3. Predict natively in T (no R/Python runtime needed for evaluation!)
  predictions = node(
    command = data |> mutate($pred = predict(data, model_r)),
    deserializer = "pmml"
  )

  -- 4. Generate a shell report
  report = shn(command = <{
    printf 'R model results cached at: %s\n' "$T_NODE_model_r/artifact"
  }>)
}

build_pipeline(p)

-- Access pipeline results
p.data           -- Native T object
p.predictions    -- Results with predictions column
```

For ONNX-based interchange, use a Python or R node to write the model and a Python, R, or T node to read it back:

```t
p = pipeline {
  model_py = pyn(
    command = <{
      from sklearn.linear_model import LogisticRegression
      clf = LogisticRegression().fit(X, y)
      clf
    }>,
    serializer = ^onnx
  )

  onnx_session = pyn(
    command = <{
      model_py
    }>,
    deserializer = ^onnx
  )
}
```

#### Debugging and Logs

When building a pipeline, T tracks the build status and logs for every node. If a node fails, you can inspect its logs directly from the T interpreter:

```t
-- Get help on log inspection
help(read_log)

-- Read the full Nix build log for a specific node
read_log("model_r")
```

The `read_log()` function requires a node name to identify which build output to retrieve. It returns the raw build output as a string, which can be printed with `cat()` to preserve formatting:

```t
cat(read_log("scored"))
```

For more comprehensive examples and templates, visit the [T Demos repository](https://github.com/b-rodrigues/t_demos).

Instead of inlining code with `command`, nodes can point to an external file using `script`. `command` and `script` are mutually exclusive, and the runtime can be inferred from file extensions such as `.R` or `.py`.

Pipeline features:
- **Automatic dependency resolution**: Nodes can be declared in any order
- **Deterministic execution**: Same inputs always produce same outputs
- **Cycle detection**: Circular dependencies are caught and reported
- **Introspection**: `pipeline_nodes()`, `pipeline_deps()`, `pipeline_node()`
- **Cross-language**: `node()`, `py()`/`pyn()`, `rn()`, and `shn()` enable execution in T, Python, R, and shell runtimes
- **Environment Variables**: Pass custom variables into Nix build sandboxes via `env_vars`
- **Re-run**: `pipeline_run()` re-executes the pipeline

You can also inspect and transform pipelines without rebuilding them from scratch:

```t
p_full = p_etl |> union(p_model)
p_trimmed = p_full |> difference(p_debug)
p_updated = p_prod |> patch(p_overrides)

pipeline_nodes(p_full)
pipeline_deps(p_full)
pipeline_to_frame(p_full)
pipeline_dot(p_full)

pipeline_validate(p_full)
```

---

## Standard Library

All packages are loaded automatically at startup:

| Package     | Functions                                               |
|-------------|----------------------------------------------------------|
| `core`      | `print`, `type`, `length`, `head`, `tail`, `map`, `filter`, `sum`, `seq`, `getwd`, `file_exists`, `dir_exists`, `read_file`, `list_files`, `env`, `path_join`, `path_basename`, `path_dirname`, `path_ext`, `path_stem`, `path_abs`, `rm` |
| `base`      | `assert`, `is_na`, `na`, `na_int`, `na_float`, `na_bool`, `na_string`, `error`, `is_error`, `error_code`, `error_message`, `error_context` |
| `math`      | `sqrt`, `abs`, `log`, `exp`, `pow`                      |
| `stats`     | `mean`, `sd`, `quantile`, `cor`, `lm`, `predict`        |
| `dataframe` | `read_csv`, `write_csv`, `colnames`, `nrow`, `ncol`, `clean_colnames` |
| `colcraft`  | `select`, `filter`, `mutate`, `arrange`, `group_by`, `summarize`, `rename`, `relocate`, `distinct`, `count`, `slice`, `pivot_longer`, `pivot_wider`, joins, missing-value helpers, factor helpers, and window functions |
| `pipeline`  | node constructors, inspection helpers, validation helpers, DAG transformations, and composition tools |
| `explain`   | `explain`, `intent_fields`, `intent_get`                |

### Selected Signatures

These signatures provide a compact map of the most commonly used functions:

#### Core, Base, and Math

- `print(value :: Any) :: NA`
- `type(value :: Any) :: String`
- `length(list :: List) :: Int`
- `head(x :: DataFrame | List | Vector, n = 6) :: DataFrame | List | Vector`
- `tail(x :: DataFrame | List | Vector, n = 6) :: DataFrame | List | Vector`
- `map(list :: List, fn :: Function) :: List`
- `filter(list :: List, fn :: Function) :: List`
- `sum(list :: List, na_rm = false) :: Number`
- `seq(start = 1, end :: Int, by = 1) :: List[Int]`
- `is_na(value :: Any) :: Bool`
- `is_error(value :: Any) :: Bool`
- `error(message :: String) :: Error`
- `pow(base :: Number, exp :: Number) :: Float`
- `sqrt(value :: Number) :: Float`
- `abs(value :: Number) :: Number`
- `rm(...) :: NA`

#### Stats and DataFrames

- `mean(vector :: Vector, na_rm = false) :: Float`
- `sd(vector :: Vector, na_rm = false) :: Float`
- `quantile(vector :: Vector, prob :: Float, na_rm = false) :: Float`
- `cor(v1 :: Vector, v2 :: Vector, na_rm = false) :: Float`
- `lm(data :: DataFrame, formula :: Formula) :: Model`
- `predict(model :: Model, data :: DataFrame) :: Vector`
- `read_csv(path :: String, clean_colnames = false) :: DataFrame`
- `write_csv(df :: DataFrame, path :: String) :: NA`
- `nrow(df :: DataFrame) :: Int`
- `ncol(df :: DataFrame) :: Int`
- `colnames(df :: DataFrame) :: List[String]`

#### Data Manipulation

- `select(df :: DataFrame, ...) :: DataFrame`
- `filter(df :: DataFrame, predicate :: NSE) :: DataFrame`
- `mutate(df :: DataFrame, ...) :: DataFrame`
- `arrange(df :: DataFrame, $col, direction = "asc") :: DataFrame`
- `group_by(df :: DataFrame, ...) :: DataFrame`
- `summarize(df :: DataFrame, ...) :: DataFrame`
- `rename(df :: DataFrame, $new = $old, ...) :: DataFrame`
- `pivot_longer(df :: DataFrame, ..., names_to = "name", values_to = "value") :: DataFrame`
- `pivot_wider(df :: DataFrame, names_from :: Symbol, values_from :: Symbol) :: DataFrame`
- `left_join(x :: DataFrame, y :: DataFrame, by = [String]) :: DataFrame`
- `drop_na(df :: DataFrame, ...) :: DataFrame`
- `replace_na(df :: DataFrame, replace :: Dict) :: DataFrame`
- `factor(x :: Vector | List, levels = [], ordered = false) :: Vector`
- `row_number(x :: Vector) :: Vector`
- `lag(x :: Vector, n = 1) :: Vector`

#### Pipelines

- `node(command :: Any, script :: String, runtime = "T", serializer = "default", deserializer = "default", functions = [], include = [], noop = false) :: Any`
- `pyn(command :: Any, script :: String, serializer = "default", deserializer = "default", functions = [], include = [], noop = false) :: Any`
- `rn(command :: Any, script :: String, serializer = "default", deserializer = "default", functions = [], include = [], noop = false) :: Any`
- `build_pipeline(pipeline :: Pipeline) :: NA`
- `pipeline_run(pipeline :: Pipeline) :: Pipeline`
- `pipeline_nodes(p :: Pipeline) :: List[String]`
- `pipeline_deps(p :: Pipeline) :: Dict`
- `pipeline_to_frame(p :: Pipeline) :: DataFrame`
- `pipeline_validate(p :: Pipeline) :: List[String]`
- `union(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`
- `difference(p1 :: Pipeline, p2 :: Pipeline) :: Pipeline`

### Math Functions

Pure numerical primitives that work on scalars and vectors:

```t
sqrt(4)        -- 2.0
abs(0 - 5)     -- 5
log(10)        -- 2.30258509299
exp(1)         -- 2.71828182846
pow(2, 3)      -- 8.0
```

### Stats Functions

Statistical summaries that work on lists and vectors. All aggregation functions support an optional `na_rm` parameter:

```t
mean([1, 2, 3, 4, 5])             -- 3.0
sd([2, 4, 4, 4, 5, 5, 7, 9])     -- 2.1380899353
quantile([1, 2, 3, 4, 5], 0.5)   -- 3.0 (median)
cor(df.x, df.y)                   -- correlation coefficient
lm(data = df, formula = y ~ x)   -- linear regression model

-- With NA handling (na_rm = true skips NA values):
mean([1, NA, 3], na_rm = true)    -- 2.0
sum([1, NA, 3], na_rm = true)     -- 4
sd([2, NA, 4, 9], na_rm = true)   -- 3.60555127546
```

### Introspection

```t
type(42)          -- "Int"
type(df)          -- "DataFrame"
explain(df)       -- detailed DataFrame summary
packages()        -- list of loaded packages
package_info("stats")  -- package details
```

### Filesystem & Path Operations

T provides a suite of functions for interacting with the filesystem and manipulating paths.

#### Filesystem

```t
getwd()                        -- "/home/user/project"
file_exists("data.csv")        -- true
dir_exists("tests")            -- true
list_files(".", pattern = ".t") -- ["test1.t", "test2.t"]
read_file("config.json")       -- "{\"port\": 8080}"
env("HOME")                    -- "/home/user"
```

#### Path Manipulation (Lexical)

These functions are purely text-based and do not check the disk.

```t
path_join("dir", "sub", "f.txt") -- "dir/sub/f.txt"
path_basename("/a/b/c.txt")      -- "c.txt"
path_dirname("/a/b/c.txt")       -- "/a/b"
path_ext("data.csv")             -- ".csv"
path_stem("data.csv")            -- "data"
path_abs("local.txt")            -- "/absolute/path/to/local.txt"
```

---

## Intent Blocks

Intent blocks provide structured metadata for LLM-assisted workflows:

```t
i = intent {
  description: "Summarize user activity",
  assumes: "Data excludes inactive users"
}

intent_fields(i)            -- Dict of all fields
intent_get(i, "description") -- specific field value
```

---

## Comments

```t
-- This is a single-line comment
```

---

## Metaprogramming

T supports Lisp-style quotation and quasiquotation for code generation and DSL building.

```t
x = 10
captured = expr(1 + !!x)
print(captured)  -- expr(1 + 10)
eval(captured)     -- 11
```

See the [Quotation Guide](quotation.md) for more details.

---

## Type Introspection

The `type()` function returns the type name of any value as a string:

```t
type(42)             -- "Int"
type(3.14)           -- "Float"
type(true)           -- "Bool"
type("hello")        -- "String"
type([1, 2])         -- "List"
type({x: 1})         -- "Dict"
type(NA)             -- "NA"
type(1 / 0)          -- "Error"
type(NA)           -- "NA"
```

---

## Next Steps

Now that you have a solid grasp of T's syntax and core features, explore these topics next:

1. **[Type System](type-system.md)** — Understand T's mode-aware type system and lambda signatures.
2. **[Pipeline Tutorial](pipeline_tutorial.md)** — Learn how to build reproducible, DAG-based data analysis workflows.
3. **[Data Manipulation Examples](data_manipulation_examples.md)** — See T's data verbs in action with worked examples.

For more hands-on examples and complete project templates, visit the [**T Demos Repository**](https://github.com/b-rodrigues/t_demos).
