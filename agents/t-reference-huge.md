

# FILE: docs/index.md

# T — The Orchestration Engine for Polyglot Data Science

**T** is an experimental orchestration engine designed for declarative, reproducible pipelines. It provides a functional Domain-Specific Language (DSL) that coordinates R, Python, and Shell nodes—with Julia support planned—within a Nix-managed infrastructure.

Unlike traditional scripting languages, T is built to be a **specifications-ready engine**, making data analysis **explicit, inspectable, and pipeline-oriented**. This unique architecture ensures that humans and LLMs can collaborate on defining high-level intent while T handles the low-level orchestration and environmental consistency.

**Status:** Version 0.51.4 "Sangoku", latest stabilization release.

---

## The Polyglot Pipeline

T's core strength is its **mandatory pipeline architecture**. To execute code in T, you typically define it as a series of nodes in a directed acyclic graph (DAG). T handles the "glue":

```t
-- A reproducible polyglot pipeline
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

-- Build the pipeline into reproducible Nix artifacts
build_pipeline(p)
```

## What is T?

T is not designed to replace your existing tools; it is designed to **orchestrate** them. It addresses the "dependency drift" and "works on my machine" syndrome by making **Nix mandatory**.

- **Orchestration, Not Invention**: Use R for its statistics, Python for its machine learning, and T to ensure they always talk to each other correctly via high-performance formats like Apache Arrow.
- **Strictly Functional & Immutable**: T eliminates side effects and mutable state. If `a = 1 / 0`, then `a` is an `Error` value, not an exception. Logic is auditable and predictable.
- **Mandatory Reproducibility**: Every node in a T pipeline runs in its own sandboxed Nix environment. T automatically detects dependencies and ensures that if a node's inputs haven't changed, its results are pulled from the cache.
- **AI-Native Design**: Through features like `intent` blocks and structured metadata, T is built for a future where humans and AI collaborate on complex data workflows.

---

## Foreign Language Nodes & Deserialization

When you define a node using `node()`, `rn()` (R), `pyn()` (Python), or `shn()` (Shell)—with Julia support planned—T treats the result as a first-class **Node** object. These objects transition through two main states:

1.  **Unbuilt Node**: A specification of what to run (command, runtime, environment variables).
2.  **Computed Node**: After `build_pipeline()`, the node points to a concrete, immutable artifact in the Nix store.

### Automatic Deserialization

When you call `read_node("node_name")` in the REPL, T looks at the node's **serializer** and attempts to automatically load the data back into the T environment:

| Serializer | Resulting T Type | Backend |
| :--- | :--- | :--- |
| `default` / `serialize` | Varies | Native T binary serialization |
| `arrow` | `DataFrame` | Apache Arrow IPC (zero-copy) |
| `csv` | `DataFrame` | Native CSV parser |
| `json` | `Dict` / `List` | JSON parser |
| `pmml` | `Model` | Native T model evaluator |

### Looking into the "Entrails"

If a node's serializer is not supported for automatic deserialization, `read_node()` returns the **Computed Node object** itself. This object contains all the metadata necessary to load the artifact manually or inspect its provenance.

You can use `explain()` to look inside a built node:

```t
-- Example: Inspecting a built R node
> model_node = p.model_r
> explain(model_node)
{
  `kind`: "computed_node",
  `name`: "model_r",
  `runtime`: "R",
  `path`: "/nix/store/...-model_r/artifact",
  `serializer`: "pmml",
  `class`: "lm",
  `dependencies`: ["data"]
}
```

The `path` field is the "escape hatch"—it gives you the absolute path to the node's output in the Nix store. You can use this to start an external interpreter and inspect the file directly, or pass it to a custom loader like `read_parquet(model_node.path)`.

---

## Documentation: The Theoretical Foundation

- [Theoretical Paper: Reproducibility-First Programming Languages](theoretical_paper.html) — the core philosophy and design principles of T.

### Getting Started
- [Getting Started Guide](getting-started.html) — first steps with T
- [Installation Guide](installation.html) — detailed setup with Nix
- [Language Overview](language_overview.html) — types, syntax, functions, and standard library
- [Type System](type-system.html) — detailed guide to T's type hierarchy and semantics
- [Numerical Arrays](arrays.html) — tutorial on N-dimensional arrays and linear algebra
- [Editor Support](editors.html) — setup guide for Vim, Emacs, and VS Code

### User Guides
- [API Reference](api-reference.html) — complete function reference by package
- [Data Manipulation Examples](data_manipulation_examples.html) — practical examples with core data verbs
- [Factors & Categorical Data](factors.html) — factor creation, level ordering, and `fct_*` helpers
- [String Manipulation](string_manipulation.html) — naming rules, examples, and exceptions for text helpers
- [Pipeline Tutorial](pipeline_tutorial.html) — step-by-step guide to T's pipeline model
- [Literate Programming with Quarto](literate-programming-quarto.html) — rendering reports from pipelines
- [Statistical Models](models.html) — linear regression, GLMs, and broom-style output
- [Plotting & Visualization](plotting.html) — ggplot2, matplotlib, and visual metadata capture
- [PMML Tutorial](pmml_tutorial.html) — move supported models between R, Python, and T
- [Handling Dates](handling_dates.html) — parsing, extraction, and date arithmetic
- [Error Handling Guide](error-handling.html) — error patterns and recovery strategies
- [Comprehensive Examples](examples.html) — real-world analysis patterns
- [T Pipeline Demos](demos.html) — interactive reports for T demo projects

### Advanced Topics
- [Reproducibility Guide](reproducibility.html) — Nix integration and reproducible workflows
- [LLM Collaboration](llm-collaboration.html) — intent blocks and AI-assisted development
- [Quotation & Metaprogramming](quotation.html) — capturing and generating code
- [Statistical Formulas](formulas.html) — formula syntax for modeling
- [Performance](performance.html) — Arrow backend and optimization
- [Performance Analysis](performance_analysis.html) — in-depth analysis of T's performance metrics
- [Composable Lenses](lens.html) — functional updates for nested structures

### Developer Resources
- [Architecture](architecture.html) — language design and implementation
- [Contributing Guide](contributing.html) — how to contribute to T
- [Development Guide](development.html) — building, testings, and debugging
- [Project Development](project_development.html) — managing T projects and workspaces
- [Package Development Guide](package_development.html) — creating and publishing T packages

### Reference & Support
- [Function Reference](reference/index.html) — exhaustive per-function guide
- [FAQ](faq.html) — frequently asked questions
- [Troubleshooting](troubleshooting.html) — common issues and solutions
- [Changelog](changelog.html) — history of changes and releases


# FILE: docs/getting-started.md

# Getting Started with T

Welcome to T! This guide will help you install T, create your first project, and understand the basic layout of a T workspace.

## Prerequisites

T requires the **Nix package manager** with flakes enabled. Nix ensures that your T environment is perfectly reproducible across Linux and macOS.

We strongly recommend installing Nix using the [Determinate Systems Nix Installer](https://install.determinate.systems/nix). For detailed, platform-specific steps, please see our:

👉 **[Nix Installation Guide](nix-installation.md)**

## Running T

As a user, you don't need to clone the repository or build the compiler from source! You can run the T shell directly from GitHub using Nix:

```bash
nix shell github:b-rodrigues/tlang
```

This command will download the T executable, fetch all required dependencies, and drop you into a temporary shell where the `t` command is available, for as long as you stay in that shell.

## Starting a New Workspace

T provides a built-in scaffolding tool to initialize your workspaces. There are two types of workspaces in T:
- **Projects**: Designed for data analysis, scripts, and reproducible pipelines.
- **Packages**: Designed for creating reusable functions and libraries to share with others.

### Creating a Project

To start a new data analysis project, navigate to your desired folder and run (while in the temporary shell you dropped in before):

```bash
t init --project my_analysis
```

The scaffolding tool will generate a reproducible workspace with the following layout:

```text
my_analysis/
├── tproject.toml       # Project configuration and dependencies
├── flake.nix           # Reproducible environment definition
├── README.md           # Project overview
├── src/
│   └── pipeline.t      # Your main analysis script
├── data/               # Place your raw data files here
├── outputs/            # Output directory for results
└── tests/              # Unit tests for your analysis
```

### Creating a Package

If you want to create a reusable library of T functions, initialize a package instead:

```bash
t init --package my_package
```

The tree layout for a package is structured for development and testing:

```text
my_package/
├── DESCRIPTION.toml    # Package metadata (name, version, exports)
├── flake.nix           # Reproducible environment definition
├── README.md           # Package overview
├── src/
│   └── main.t          # Package source code
├── tests/
│   └── test-my_package.t  # Unit tests for your package
├── examples/           # Usage examples
└── docs/               # Documentation
```

## Running Your Code

Now that you’ve bootstrapped your project or package, you can leave the temporary Nix shell using `exit`.
Move into the project’s directory (if not there already), and type `nix develop` to drop into the development environment of the project.
You may be prompted to make the `flake.nix` discoverable, you can copy and paste the suggested command or
simply run `git add .` to stage the whole project. Try `nix develop` again to drop into the development
environment. You should see the following:

```bash
==================================================
T Project: start_t
==================================================

Available commands:
  t repl              - Start T REPL
  t run <file>        - Run a T file
  t test              - Run tests

To add dependencies:
  * Add them to tproject.toml
  * Run 't update' to sync flake.nix

```

Inside your project or package directory, you can start the interactive REPL to explore your data:

```bash
t repl
```

(or simply `t`).

To execute a script from end-to-end, use:

```bash
t run scripts/main.t
```

## Next Steps

Now that you have your first project set up and understand the folder structure, you are ready to explore the language features and build reproducible data pipelines!

1. **[Configure Editors](editors.md)** — Configure your editor to play well with T.
2. **[Language Overview](language_overview.md)** — Explore T's syntax, types, and standard library functions.
3. **[Pipeline Tutorial](pipeline_tutorial.md)** — Learn how to build reproducible, DAG-based data analysis workflows (the core feature of T).
4. **[Project Development](project_development.md)** — Dive deeper into managing your `tproject.toml` and Nix environments.


# FILE: docs/language_overview.md

# T Language Overview

> **Version**: 0.51.4

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

> [!IMPORTANT]
> **Strict Scalar Equality**: The equality operators `==` and `!=` are defined for **scalars only**. If either operand is a collection (List, Vector, or NDArray), the operator will return a `TypeError`. To perform element-wise comparisons or check equality against a collection, you **must** use the broadcasting operators `.==` and `.!=`.
>
> ```t
> 1 == [1, 2]    -- Error: Operator '==' is defined for scalars only.
> 1 .== [1, 2]   -- [true, false]
> ```
>
> **Deep Equality**: To check if two complex objects are structurally identical (including all elements and metadata), use the `identical()` function. This is the recommended way to compare Lists, Vectors, or DataFrames for identity.
>
> ```t
> v1 = [1, 2, 3]
> v2 = [1, 2, 3]
> identical(v1, v2)   -- true
> ```

### Boolean Logic

```t
true and true   -- true
true and false  -- false
false or true   -- true
not true        -- false
```

### Vectorized Logic

For element-wise logical operations on collections, use the designated broadcasting operators:

| Operator | Description | Scalar Equivalent |
|----------|-------------|-------------------|
| `.&`     | Vectorized AND | `and` (or `&&`)  |
| `.|`     | Vectorized OR  | `or` (or `||`)   |

> [!TIP]
> **No Silent Magic**: Just like arithmetic and comparison, the bitwise operators `&` and `|` strictly require scalar operands. Attempting to use them with a List or Vector will result in a `TypeError` that directs you to use the vectorized `.&` or `.|` operators.

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

### Auto-Quotation (`$param`)

T supports auto-quoting for function parameters. Prefixing a parameter with `$` indicates that the caller can pass a bare name (like a column name), which is automatically captured as a **Symbol** rather than being evaluated.

```t
my_select = \(df, $col) select(df, col)

-- Caller passes bare 'salary' which is captured as a symbol
my_select(df, salary)
```

This is particularly useful when writing wrappers around data verbs like `select` or `mutate`. See [Quotation and Metaprogramming](quotation.md) for more advanced usage involving `!!` (unquote).

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

---

## Data Access and Lenses

T provides a unified retrieval system via the `get()` primitive and the **Lens** library. Lenses allow you to focus on specific parts of complex data structures (DataFrames, Lists, Pipelines) and perform serializable, cross-node data operations.

### The Unified `get()` Built-in

The `get()` function is the primary entry point for retrieving data. It supports several modes of operation:

#### 1. Variable Lookup (R-style)
```t
salary = 50000
get("salary")                -- 50000
get(sym("salary"))           -- 50000
```

#### 2. Collection Indexing (0-based)
```t
lst = [10, 20, 30]
get(lst, 1)                  -- 20
```

#### 3. Pipeline Node Access
```t
p = pipeline { a = 1, b = 2 }
get(p, "a")                  -- 1
```

#### 4. Lens Focus
```t
l = col_lens("mpg")
get(mtcars, l)               -- Vector of 'mpg' column
```

### Lenses

Lenses are structured, serializable "addressing" objects. Unlike standard property access (`obj.prop`), lenses can be composed and passed between pipeline nodes.

#### Built-in Lenses

| Creator | Target | Description |
|---------|--------|-------------|
| `col_lens(name)` | `DataFrame`, `Dict`, `List` | Targets a column or key by name. |
| `idx_lens(i)` | `List`, `Vector` | Targets an element by index. |
| `row_lens(i)` | `DataFrame` | Targets a specific row as a Dictionary. |
| `node_lens(name)` | `Pipeline` | Targets a specific node within a pipeline. |
| `env_var_lens(n, v)`| `Pipeline` | Targets an environment variable `v` from node `n`. |

#### Composition and Transformation

Lenses can be composed using `compose()` to reach deep into nested structures. To update data through a lens, use the `over()` function.

```t
-- Deep access
data = [users: [Alice: [id: 1], Bob: [id: 2]]]
l_deep = compose(col_lens("users"), col_lens("Alice"), col_lens("id"))
get(data, l_deep)            -- 1

-- Deep update
data_updated = over(data, l_deep, \(x) 99)
get(data_updated, l_deep)    -- 99
```

> [!NOTE]
> **Serializable Pipelines**: Tlang lenses are now implemented as structured data (`VLens`), not closures. This ensures they can be saved to disk by one pipeline node and loaded by another without losing functionality.

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


# FILE: docs/installation.md

# Installation Guide

Complete guide for installing and setting up the T programming language.

## System Requirements

### Operating System
- **Linux** (recommended): Any modern distribution (Ubuntu 20.04+, Fedora 35+, Arch, etc.)
- **macOS**: 11 (Big Sur) or later
- **Windows**: Via WSL2 (Windows Subsystem for Linux)

### Prerequisites
- **Nix package manager** 2.4 or later with flakes enabled
- **Git** for version control
- At least **2GB free disk space** for Nix store
- **Internet connection** for initial setup

## Step 1: Install Nix

T requires the **Nix package manager** with flakes enabled. We strongly recommend using the **Determinate Systems Nix Installer** for its robustness and ease of use.

### Platform-Specific Nix Installation

For detailed instructions on installing Nix on **Linux**, **macOS**, and **Windows (WSL2)**, please see our dedicated:

👉 **[Nix Installation Guide](nix-installation.md)**

Once Nix is installed and flakes are enabled, you can proceed to Step 2.

### Troubleshooting Nix Installation

#### Enabling Experimental Features
If you're using the standard Nix installer (not the Determinate Systems one), you might see an error that `nix shell` or other commands are not recognized. You can enable the required features by adding them to your Nix configuration or by appending a flag to each command:

**Option 1: Add to config (Recommended)**
```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

**Option 2: Use a command flag**
Append `--extra-experimental-features "nix-command flakes"` to your Nix commands.

#### Trusted Users and Binary Caches
If you see warnings like `ignoring untrusted substituter`, it means you need to add yourself as a trusted user so Nix allows you to use the T binary cache. On macOS, you can run the following one-liner:

```bash
echo "trusted-users = root $USER" | sudo tee -a /etc/nix/nix.custom.conf && sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

This works for both standard Nix installations and Determinate Nix installations. If you see warnings like `ignoring untrusted substituter`, this means the `trusted-users` configuration is not in place.

## Step 3: Clone T Repository

```bash
# Choose a directory for T (e.g., ~/projects)
mkdir -p ~/projects
cd ~/projects

# Clone the repository
git clone https://github.com/b-rodrigues/tlang.git
cd tlang
```

## Step 4: Enter Development Environment

The Nix flake provides a complete, isolated development environment:

```bash
nix develop
```

**First run** will take several minutes to:
- Download and compile OCaml toolchain
- Build Apache Arrow and dependencies
- Set up development tools (dune, menhir, etc.)

All dependencies are cached in the Nix store (`/nix/store/`) and reused for future sessions.

**Expected output:**

```
warning: creating lock file '/home/user/projects/tlang/flake.lock'
...
(nix development shell activated)
```

## Step 5: Build T

Inside the development environment:

```bash
dune build
```

This compiles:
- Lexer and parser
- Evaluator and runtime
- Standard library packages
- REPL

**Expected output:**

```
File "src/repl.ml", line 1, characters 0-0:
Building...
```

Build artifacts are placed in `_build/default/`.

## Step 6: Verify Installation

### Start the REPL

```bash
dune exec src/repl.exe
```

You should see:

```
T, a reproducibility-first orchestration engine for polyglot
data science and statistical analysis.
Version 0.51.1 "Sangoku" using Nix <nix-version>
Licensed under the EUPL v1.2. No warranties.
This software is in beta and is entirely LLM-generated — caveat emptor.
Website: https://tstats-project.org
Contributions are welcome!
Type :quit or :q to exit, :help for commands.

T> 
```

### Test Basic Operations

```t
> 2 + 3
5

> [1, 2, 3] |> sum
6

> type(42)
"Int"

> exit
```

If all commands work, installation is successful! 🎉

## Step 7: Run Tests (Optional)

Verify everything works correctly:

```bash
dune runtest
```

Expected behavior:
- All tests should pass
- Golden tests compare T output against R results
- Test execution may take 1-2 minutes

## Development Workflow

### Entering the Environment

Every time you want to work with T:

```bash
cd ~/projects/tlang
nix develop
```

### Updating Dependencies

If `flake.nix` changes (e.g., after pulling updates):

```bash
nix flake update
nix develop
```

### Cleaning Build Artifacts

```bash
dune clean
dune build
```

## Advanced Configuration

### Direnv Integration (Optional)

Automatically enter the Nix shell when entering the directory:

```bash
# Install direnv
nix-env -iA nixpkgs.direnv

# Enable direnv in your shell (bash/zsh)
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc  # for bash
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc   # for zsh

# Create .envrc in tlang directory
cd ~/projects/tlang
echo "use flake" > .envrc
direnv allow
```

Now `cd tlang` automatically activates the environment.

### Binary Cache (Faster Builds)

T doesn't yet have a public binary cache, but you can set one up locally for your team:

```bash
# In nix.conf
substituters = https://cache.nixos.org/ https://your-cache.example.com/
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

## Troubleshooting

### "command not found: nix"

The Nix installation may not have updated your PATH. Try:

```bash
source ~/.nix-profile/etc/profile.d/nix.sh
```

Or restart your terminal.

### "experimental-features" Error

Flakes aren't enabled. Double-check `~/.config/nix/nix.conf`:

```bash
cat ~/.config/nix/nix.conf
# Should contain: experimental-features = nix-command flakes
```

### "nix develop" Hangs

Nix is building dependencies from source. This is normal on first run. Check progress:

```bash
nix develop --show-trace
```

Or use a faster binary cache (if available).

### Build Fails with Dune Errors

Clean and rebuild:

```bash
dune clean
rm -rf _build
dune build
```

If errors persist, check:
- You're inside `nix develop` shell
- OCaml version: `ocaml --version` should be 4.14+
- Dune version: `dune --version` should be 3.0+

### Arrow FFI Issues

T uses Apache Arrow C GLib bindings. If you see linking errors:

```bash
# Inside nix develop
pkg-config --modversion arrow-glib
# Should output: 10.0.0 or similar
```

The Nix flake ensures Arrow is available; these errors usually indicate you're not in the Nix shell.

### Tests Failing

Some tests require R (for golden test comparisons). Check test logs:

```bash
dune runtest --verbose
```

Known issues:
- Floating-point precision differences across platforms
- R package availability for comparison tests

## Platform-Specific Notes

### macOS

- **Apple Silicon (M1/M2)**: Fully supported via Nix's ARM64 support
- **Rosetta**: Not required; native ARM builds are used

### WSL2

- **File permissions**: Ensure cloned repo is on Linux filesystem (`/home/user/...`), not Windows mount (`/mnt/c/...`)
- **Performance**: Native Linux filesystem is significantly faster

### NixOS

T works natively on NixOS:

```nix
# Add to configuration.nix or home-manager
environment.systemPackages = with pkgs; [
  # T will be added to nixpkgs eventually
];
```

For now, use `nix develop` as above.

## Next Steps

Now that T is installed:

1. **[Getting Started Guide](getting-started.md)** — Write your first program
2. **[Language Overview](language_overview.md)** — Learn T syntax
3. **[Examples](examples.md)** — See practical code

## Uninstalling

### Remove T Repository

```bash
rm -rf ~/projects/tlang
```

### Remove Nix Store Entries

```bash
# Remove just T's dependencies (preserves other Nix packages)
nix-store --gc

# Or remove all unused packages
nix-collect-garbage -d
```

### Uninstall Nix Completely

```bash
# For multi-user install
sudo rm -rf /nix
sudo rm /etc/profile.d/nix.sh
sudo rm /etc/nix

# For single-user install
rm -rf ~/.nix-profile ~/.nix-defexpr ~/.nix-channels ~/.config/nix
```

---

**Ready to start?** Head to the [Getting Started Guide](getting-started.md)!


# FILE: docs/api-reference.md

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

## Lens Package

Composable access and update lenses for dictionaries, lists, data frames, and pipeline inspection.

For the full walkthrough and worked examples, see the [Lens guide](lens.md). For the generated per-function entries, see the [Function Reference](reference/index.md).

Common lens entry points include:

- `col_lens(name)` — focus a dictionary key or data-frame column
- `idx_lens(i)` — focus a list/vector position
- `compose(l1, l2, ...)` — build larger traversals from smaller ones
- `get(data, lens)` — read through a lens
- `set(data, lens, value)` / `over(data, lens, fn)` — update through a lens
- `filter_lens(predicate)` — keep only matching elements inside a focused collection

---

## Pipeline Package

Pipeline introspection and management.

### `which_nodes(p, predicate)`

Filter the richer node records from `read_pipeline(p).nodes` without manually writing `read_pipeline`, `compose`, or an explicit lambda.

Instead of writing:

```t
pipe_info = read_pipeline(p)

errored_nodes_l = compose(
  col_lens("nodes"),
  filter_lens(\(node) !is_na(node.diagnostics.error))
)

get(pipe_info, errored_nodes_l)
```

you can simply do this:

```t
which_nodes(p, !is_na(diagnostics.error))
```

This is the diagnostics-friendly companion to `filter_node`:

- `filter_node` returns a new `Pipeline`
- `which_nodes` returns a `List` of node records

Each node record exposes:

- `name`
- `value`
- `diagnostics`

**Parameters:**

- `p` — The pipeline to inspect
- `predicate` — A predicate over node records

**Returns:**

`List` — Matching node records

**Examples:**

```t
which_nodes(p, !is_na(diagnostics.error))
which_nodes(p, name == "model")

has_error = \(node) !is_na(node.diagnostics.error)
which_nodes(p, has_error)
```

### `errored_nodes(p)`

Convenience wrapper returning the subset of node records whose `diagnostics.error` is not `NA`.

**Parameters:**

- `p` — The pipeline to inspect

**Returns:**

`List` — Node records with captured errors

**Examples:**

```t
errored_nodes(p)
errored_nodes(p) |> map(\(node) node.name)
```

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


# FILE: docs/pipeline_tutorial.md

# Pipeline Tutorial

> A step-by-step guide to T's pipeline execution model

Pipelines are T's core execution model. They let you define named computation steps (nodes) that are automatically ordered by their dependencies, executed deterministically, and cached for re-use.

---

## 1. Your First Pipeline

A pipeline is a block of named expressions enclosed in `pipeline { ... }`:

```t
p = pipeline {
  x = 10
  y = 20
  total = x + y
}
```

This creates a pipeline with three nodes: `x`, `y`, and `total`. Each node is computed once, and the results are cached. Access any node's value with dot notation:

```t
p.x      -- 10
p.y      -- 20
p.total  -- 30
```

The pipeline itself displays as:

```
Pipeline(3 nodes: [x, y, total])
```

---

## 2. Explicit Node Configuration

In addition to bare assignments, you can explicitly configure nodes using the `node()` function. This lets you define the execution environment (like the `runtime`) and custom serialization methods for when a pipeline is materialized by Nix:

```t
p = pipeline {
  data = node(command = read_csv("data.csv"), runtime = T)
  
  -- Running a Python node that trains a model using the pyn wrapper
  model = pyn(
    command = <{
        from sklearn.linear_model import LinearRegression
        fit = LinearRegression().fit(X, y)
        fit
    }>,
    serializer = "pmml"
  )
}
```

Bare syntax (like `x = 10`) is automatically desugared to `x = node(command = 10, runtime = T, serializer = default, deserializer = default)`. You can also use `pyn()`, `rn()`, and `shn()` as shortcuts for Python, R, and shell runtimes. T enforces cross-runtime safety: if a node with a non-`T` runtime depends on a `T` node, or vice versa, you should specify an explicit `serializer`/`deserializer`.

When an R node returns a `ggplot2` object, or a Python node returns a `matplotlib` / `plotnine` plot object, T now preserves lightweight plot metadata for REPL inspection. Reading or printing those artifacts shows a structured summary with the plot class (`ggplot`, `matplotlib`, or `plotnine`), runtime backend (`R` or `Python`), title, aesthetic mappings, labels, and layer information instead of a raw runtime-specific object dump.

### Using the `script` Argument

Instead of inlining code with `command`, you can point a node to an external source file using the `script` argument. This works with `node()`, `pyn()`, `rn()`, and `shn()`. The `script` and `command` arguments are mutually exclusive.

```t
p = pipeline {
  -- Execute an external R script
  model = rn(script = "train_model.R", serializer = "pmml")

  -- Execute an external Python script
  predictions = pyn(script = "predict.py", deserializer = "pmml")

  -- Execute an external shell script
  report = shn(script = "postprocess.sh")

  -- node() auto-detects the runtime from the file extension
  summary = node(script = "summarise.R", serializer = "json")
}
```

When using `script`, the runtime is auto-detected from the file extension (`.R` → R, `.py` → Python, `.sh` → sh) if not explicitly set via the `runtime` argument. T reads the script file to extract identifier references, allowing the pipeline dependency graph to be built correctly from variables referenced in the external file.

### Shell / Bash nodes with `shn()`

Use `shn()` for pipeline steps that are easiest to express as shell or CLI commands. It is a convenience wrapper around `node(runtime = sh, ...)`, just like `rn()` and `pyn()` wrap `node()` for R and Python.

```t
p = pipeline {
  -- Exec-style shell node: command + positional argv
  fields = shn(
    command = "printf",
    args = ["first line\\nsecond line\\n"]
  )

  -- Script-style shell node: inline shell source executed with `sh`
  report = shn(command = <{
#!/bin/sh
set -eu

# Dependencies for T's lexical pipeline analysis: summary_r summary_py
printf 'R summary: %s\n' "$T_NODE_summary_r/artifact"
printf 'Python summary: %s\n' "$T_NODE_summary_py/artifact"
  }>)
}
```

There are two useful modes:

- **Exec mode**: provide a string `command` plus `args = [...]` to run a program directly with positional arguments.
- **Shell mode**: provide raw shell source with `<{ ... }>` or a `.sh` `script`, optionally overriding the interpreter with `shell = "bash"` and `shell_args = ["-lc"]` when you need Bash-specific syntax.

Shell nodes default to `serializer = text`, which makes them a good fit for reports, command output, and glue code between other pipeline nodes. For a full end-to-end example that mixes T, R, Python, and `sh`, see `tests/pipeline/polyglot_shell_pipeline.t` and `.github/workflows/polyglot-shell-pipeline.yml`.

---

## 3. Cross-Language Integration

T is designed to orchestrate code across multiple languages. The pipeline runner manages the serialization and deserialization of data between R, Python, and T using a first-class serializer system. For a deep dive into how T handles data interchange, see the [Serializers Documentation](serializers.md).

### Interchange Formats Comparison

| Format | Option | Best For | Requirement |
|---|---|---|---|
| **T Native** | `"default"` | T-to-T communication | None |
| **Arrow** | `"arrow"` | Large DataFrames | `pyarrow` (Py), `arrow` (R) |
| **PMML** | `"pmml"` | Predictive Models | `sklearn2pmml` (Py), `r2pmml` (R) |
| **JSON** | `"json"` | Simple lists/dicts | `jsonlite` (R) |

### Example: Training in R, Predicting in T

You can train a model in R and use T's native OCaml model evaluator to make predictions without leaving the T runtime:

```t
p = pipeline {
  -- Node 1: Train model in R using the rn wrapper
  model_r = rn(
    command = <{
      data <- read.csv("data.csv")
      lm(mpg ~ wt + hp, data = data)
    }>,
    serializer = "pmml"
  )
  
  -- Node 2: Predict in T using the R model
  predictions = node(
    command = <{
      test_df = read_csv("new_data.csv")
      predict(test_df, model_r)
    }>,
    runtime = "T",
    deserializer = "pmml"
  )
}
```

Setting `deserializer = "pmml"` on the T node tells the pipeline runner to use T's native PMML parser to convert the R model into a T model object.

---

## 4. Automatic Dependency Resolution

Nodes can be declared in **any order**. T automatically resolves dependencies:

```t
p = pipeline {
  result = x + y   -- depends on x and y
  x = 3            -- defined after result
  y = 7            -- defined after result
}
p.result  -- 10
```

T builds a dependency graph and executes nodes in topological order, so `x` and `y` are computed before `result` regardless of declaration order.

---

## 5. Chained Dependencies

Nodes can depend on other computed nodes, forming chains:

```t
p = pipeline {
  a = 1
  b = a + 1     -- depends on a
  c = b + 1     -- depends on b
  d = c + 1     -- depends on c
}
p.d  -- 4
```

---

## 6. Pipelines with Functions

Nodes can use any T function, including standard library functions:

```t
p = pipeline {
  data = [1, 2, 3, 4, 5]
  total = sum(data)
  count = length(data)
}
p.total  -- 15
p.count  -- 5
```

---

## 7. Pipelines with Pipe Operators

The pipe operator `|>` works naturally inside pipelines:

```t
double = \(x) x * 2

p = pipeline {
  a = 5
  b = a |> double
}
p.b  -- 10
```

### Error Recovery with Maybe-Pipe

The maybe-pipe `?|>` forwards all values — including errors — to the next function.
This is useful for building recovery logic into pipelines:

```t
recovery = \(x) if (is_error(x)) 0 else x
double = \(x) x * 2

p = pipeline {
  raw = 1 / 0                    -- Error: division by zero
  safe = raw ?|> recovery        -- forwards error to recovery → 0
  result = safe |> double        -- 0 |> double → 0
}
p.safe    -- 0
p.result  -- 0
```

Without `?|>`, the error from `raw` would short-circuit at `|>` and never reach `recovery`. The maybe-pipe lets you intercept errors and provide fallback values.

---

## 8. Data Pipelines

Pipelines are most powerful for data analysis workflows. Here's a complete example loading, transforming, and summarizing data:

```t
p = pipeline {
  data = read_csv("employees.csv")
  rows = data |> nrow
  cols = data |> ncol
  names = data |> colnames
}

p.rows   -- number of rows
p.cols   -- number of columns
p.names  -- list of column names
```

### Full Data Analysis Pipeline

```t
p = pipeline {
  raw = read_csv("sales.csv")
  filtered = filter(raw, $amount > 100)
  by_region = filtered |> group_by($region)
  summary = by_region |> summarize($total = sum($amount))
}

p.summary  -- DataFrame with regional totals
```

---

## 9. Pipeline Introspection

T provides functions to inspect pipeline structure:

### List all nodes

```t
p = pipeline { x = 10; y = 20; total = x + y }
pipeline_nodes(p)  -- ["x", "y", "total"]
```

### View dependency graph

```t
pipeline_deps(p)
-- {`x`: [], `y`: [], `total`: ["x", "y"]}
```

### Access a specific node by name

```t
pipeline_node(p, "total")  -- 30
```

---

## 10. Re-running Pipelines

Use `pipeline_run()` to re-execute a pipeline:

```t
p2 = pipeline_run(p)
p2.total  -- 30 (re-computed)
```

Re-running produces the same results — T pipelines are deterministic.

---

## 11. Deterministic Execution

Two pipelines with the same definitions always produce the same results:

```t
p1 = pipeline { a = 5; b = a * 2; c = b + 1 }
p2 = pipeline { a = 5; b = a * 2; c = b + 1 }
p1.c == p2.c  -- true
```

---

## 12. Error Handling & Resilience

### Errors are Values

In T, errors are **first-class values**. By default, evaluation is **resilient**: if a node fails, it produces an `Error` value instead of crashing the pipeline. This allows other independent nodes to continue building, giving you a full picture of which parts of your DAG are healthy.

```t
p = pipeline {
  a = 1 / 0      -- Produces an Error(DivisionByZero)
  b = 1 + 1      -- Still succeeds! (2)
  c = a + 1      -- Fails because 'a' is an error (Error)
}
```

When you print or build this pipeline, T provides a summary of which nodes succeeded and which failed.

### The `--failfast` Flag

If you prefer the usual, common behaviour where evaluation stops immediately at the first error, you can use the `--failfast` flag:

```bash
$ t run --failfast src/pipeline.t
```

In your T scripts, you can also opt-in to this behavior via `t_make()`:

```t
t_make(failfast = true)
```

### Cycle Detection

T detects circular dependencies and reports them at construction time, before any nodes are executed:

```t
pipeline {
  a = b
  b = a
}
-- Error(ValueError: "Pipeline has a dependency cycle involving node 'a'")
```

### Missing Nodes

Accessing a non-existent node returns a structured error:

```t
p = pipeline { x = 10 }
p.nonexistent
-- Error(KeyError: "node 'nonexistent' not found in Pipeline")
```

---

## 13. Materializing Pipelines

Defining a pipeline with `pipeline { ... }` evaluates nodes in-memory. To **materialize** them as reproducible Nix artifacts (potentially using R or Python dependencies you've defined in `tproject.toml`), use `populate_pipeline()` with the `build = true` argument:

```t
p = pipeline {
  data = read_csv("sales.csv")
  total = sum(data.$amount)
}

populate_pipeline(p, build = true)
```

`populate_pipeline(p, build = true)` is the primary command for materializing a pipeline. It does the following:

1. **Populates** the `_pipeline/` directory with `pipeline.nix` and `dag.json`.
2. **Generates** a Nix expression with one derivation per node. Crucially, if you define `[r-dependencies]` or `[py-dependencies]` in your `tproject.toml`, pipeline nodes have access to these language environments!
3. **Triggers** a Nix build to materialize each node as a serialized artifact.
4. **Records** the build in a timestamped log file (`_pipeline/build_log_YYYYMMdd_HHmmss_hash.json`).

> [!NOTE]
> `build_pipeline(p)` is available as a shorthand for `populate_pipeline(p, build = true)`.

### Reading built artifacts

After building, use `read_node()` or `load_node()` to retrieve materialized values:

```t
read_node("total")   -- reads the serialized artifact for "total"
load_node("total")   -- same as read_node, loads the artifact
```

These functions look up the node in the **latest build log** and deserialize the artifact.

---

## 14. Orchestrating with populate_pipeline()

For more control over the build process, T provides `populate_pipeline()`. This function prepares the pipeline infrastructure without necessarily triggering the Nix build immediately.

```t
populate_pipeline(p)                -- Prepares _pipeline/ only
populate_pipeline(p, build = true)  -- Same as build_pipeline(p)
```

### The `_pipeline/` directory

T maintains a persistent state directory for your pipeline. When you populate or build, T creates:

- **`_pipeline/pipeline.nix`**: The generated Nix expression for your pipeline nodes.
- **`_pipeline/dag.json`**: A machine-readable dependency graph of your pipeline.
- **`_pipeline/build_log_*.json`**: History of previous successful builds.

---

## 15. Build Logs and Time Travel

T keeps a history of your builds in `_pipeline/`. This enables **Time Travel** — the ability to read artifacts from specific past versions of your pipeline.

### Inspecting logs
Use `list_logs()` to see available build logs:

```t
logs = list_logs()
-- DataFrame of build logs with filename, modification_time, and size_kb
```

Use `inspect_pipeline()` to view the build status of a specific pipeline as a DataFrame (defaults to the latest):

```t
inspect_pipeline()
-- DataFrame(5 rows x 4 cols: [derivation, build_success, path, output])

inspect_pipeline(which_log = "20260221_143022")
```

### Reading from a specific build

Pass the `which_log` argument to `read_node()` to specify which build to read from. You can pass a regex pattern or a specific filename:

```t
-- Read the latest version (default)
val = read_node("result")

-- Read from a specific historical build
val_old = read_node("result", which_log = "20260221_143022")
```

This ensures that even as you update your code and data, you can always recover and compare results from previous runs.

---

## 16. Execution Modes

T enforces a clear separation between interactive and non-interactive execution:

### Non-interactive (`t run`)

Scripts executed with `t run` **must** call `populate_pipeline()` (or `build_pipeline()`). This ensures that non-interactive execution always produces reproducible Nix artifacts. By default, `t run` operates in **resilient mode**, continuing past errors to provide a full diagnostic summary. Use `--failfast` to change this.

```bash
# ✅ This works — resilient by default
$ t run my_pipeline.t

# 🛑 This fails immediately on the first error
$ t run --failfast my_pipeline.t

# ❌ This is rejected — script doesn't call populate_pipeline()
$ t run my_script.t
# Error: non-interactive execution requires a pipeline.
# Use --unsafe to override.
```

A valid pipeline script looks like:

```t
-- my_pipeline.t
p = pipeline {
  data = read_csv("input.csv")
  result = data |> filter($value > 0) |> summarize(total = sum($value))
}

populate_pipeline(p, build = true)
```

### Interactive (REPL)

The REPL is **unrestricted** — you can run any T code line by line, whether or not it involves pipelines:

```bash
$ t repl
T> x = 1 + 2
T> print(x)
3
T> p = pipeline { a = 10 }
T> p.a
10
```

---

## 17. Using Imports in Pipelines

When a pipeline is built with `build_pipeline()`, each node runs inside a **Nix sandbox** — an isolated build environment. Import statements from your script are **automatically propagated** into each sandbox, so imported packages and functions are available to all nodes.

```t
-- pipeline.t
import my_stats
import data_utils[read_clean, normalize]

p = pipeline {
  raw = read_csv("data.csv")
  clean = read_clean(raw)              -- uses imported function
  normed = normalize(clean)            -- uses imported function
  result = weighted_mean(normed.$x, normed.$w)  -- uses imported function
}

build_pipeline(p)
```

When `build_pipeline(p)` generates the Nix derivation for each node, it prepends the import statements:

```t
-- Generated node_script.t (inside Nix sandbox)
import my_stats
import data_utils[read_clean, normalize]
raw = deserialize("$T_NODE_raw/artifact.tobj")
result = weighted_mean(raw.$x, raw.$w)
serialize(result, "$out/artifact.tobj")
```

All three import forms are supported:

| Syntax | Effect |
|---|---|
| `import "src/helpers.t"` | Import a local file |
| `import my_stats` | Import all public functions from a package |
| `import my_stats[foo, bar]` | Import specific functions |
| `import my_stats[wm=weighted_mean]` | Import with aliases |

---

## 18. Using explain() with Pipelines

The `explain()` function provides structured metadata about pipelines:

```t
p = pipeline {
  x = 10
  y = x + 5
  z = y * 2
}

e = explain(p)
e.kind        -- "pipeline"
e.node_count  -- 3
```

---

## 19. Skipping Nodes

You can explicitly skip a node (and by extension, all nodes that depend on it) by passing the `noop = true` argument to the `node()` function.

```t
p = pipeline {
  raw_data = read_csv("raw.csv")
  
  # This node and its dependencies won't trigger a heavy Nix build
  expensive_model = rn(
    command = train(raw_data),
    noop = true
  )

  # This node depends on expensive_model, therefore it becomes a noop as well
  report = rn(command = generate_report(expensive_model))
}

populate_pipeline(p, build = true)
```

In a Nix sandbox context, `noop` generates a lightweight stub instead of a real build derivation.

---

## 20. Node Metadata

Every node in a pipeline carries structured metadata that you can query and manipulate. The `pipeline_to_frame()` function converts this metadata into a DataFrame with one row per node.

### `pipeline_to_frame`

```t
p = pipeline { a = 1; b = a + 1; c = b + 1 }
pipeline_to_frame(p)
-- DataFrame(3 rows x 8 cols: [name, runtime, serializer, deserializer, noop, deps, depth, command_type])
```

The columns returned are:

| Column | Type | Description |
|---|---|---|
| `name` | String | Unique node identifier |
| `runtime` | String | `"T"`, `"R"`, or `"Python"` |
| `serializer` | String | e.g. `"default"`, `"pmml"` |
| `deserializer` | String | e.g. `"default"`, `"pmml"` |
| `noop` | Bool | Whether the node is a no-op |
| `deps` | String | Comma-separated dependency names |
| `depth` | Int | Topological depth (roots = 0) |
| `command_type` | String | `"command"` or `"script"` |

`pipeline_to_frame` is the foundation for inspection: you can use T's standard `filter`, `select`, and `arrange` verbs on the resulting DataFrame.

### `pipeline_summary`

`pipeline_summary(p)` is a convenience alias for `pipeline_to_frame(p)`:

```t
pipeline_summary(p)
-- same output as pipeline_to_frame(p)
```

### `select_node`

`select_node` returns a DataFrame with only the columns you request, using NSE `$field` references:

```t
p = pipeline {
  a = 1
  b = node(command = <{ 2 }>, runtime = R, serializer = "pmml")
  c = b + 1
}

p |> select_node($name, $runtime, $depth)
-- DataFrame: name="a", runtime="T", depth=0
--            name="b", runtime="R", depth=0
--            name="c", runtime="T", depth=1
```

Available fields: `$name`, `$runtime`, `$serializer`, `$deserializer`, `$noop`, `$deps`, `$depth`, `$command_type`.

---

## 21. Environment Variables

Pipeline nodes can pass environment variables into the Nix build sandbox via the `env_vars` named argument on `node()`, `py()`/`pyn()`, and `rn()`. This allows nodes to configure their build-time execution environment without embedding those values directly into the command body.

```t
p = pipeline {
  model = rn(
    command = <{ train_model(data) }>,
    env_vars = [
      MODEL_MODE: "train",
      RETRIES: 2,
      DEBUG: true
    ]
  )
}
```

### Supported Types

The `env_vars` dictionary supports the following scalar-like values:

| Type | Example | Nix Output |
|---|---|---|
| **String** | `"train"` | `"train"` |
| **Symbol** | `train` | `"train"` |
| **Int** | `2` | `"2"` |
| **Float** | `3.14` | `"3.14"` (up to 15 significant digits) |
| **Bool** | `true` | `"true"` |
| **NA** | `NA` | (Omitted from derivation) |

### Validation

T performs early validation on environment variables:
- `env_vars` must be a dictionary.
- Unsupported types (like Lists or nested Dicts) trigger a structured type error during pipeline construction.
- `NA` values are silently omitted from the generated Nix derivation instead of being materialized as empty strings.

These variables are automatically threaded into the generated `stdenv.mkDerivation` and are available via standard system methods (e.g., `Sys.getenv()` in R or `os.environ` in Python) during the Nix build step.

---

## 22. Node-Level Operations (`_node` family)


T provides a set of colcraft-style verbs for operating on pipeline nodes. These mirror the DataFrame API, using NSE `$field` references for node metadata fields.

### `filter_node`

Returns a new pipeline containing only the nodes where the predicate is true. No DAG validity check is performed — if a retained node references a removed node, that surfaces at `build_pipeline` time.

```t
p = pipeline {
  load   = read_csv("data.csv")
  model  = rn(command = <{ lm(y ~ x, data = load) }>, serializer = "pmml")
  score  = node(command = predict(model, load), deserializer = "pmml")
}

-- Keep only R nodes
p |> filter_node($runtime == "R") |> pipeline_nodes
-- ["model"]

-- Keep only nodes with no noop flag
p |> filter_node($noop == false) |> pipeline_nodes

-- Keep only shallow nodes (root and depth-1 nodes)
p |> filter_node($depth <= 1) |> pipeline_nodes
```

### `which_nodes`

`filter_node` rewrites the pipeline itself. `which_nodes` is the read-only counterpart: it filters the richer node records you would otherwise have to access manually through `read_pipeline(p).nodes`.

This is especially useful for diagnostics queries because each record includes `name`, `value`, and `diagnostics`.

```t
p = pipeline {
  bad = 1 / 0
  ok = 42
  downstream = bad + 1
}

-- Keep only nodes with captured errors
which_nodes(p, !is_na(diagnostics.error))

-- Same idea, but return only the node names
which_nodes(p, !is_na(diagnostics.error))
  |> map(\(node) node.name)
-- ["bad", "downstream"]

-- Explicit predicate functions still work too
has_error = \(node) !is_na(node.diagnostics.error)
which_nodes(p, has_error)

-- Convenience shortcut for the most common case
errored_nodes(p) |> map(\(node) node.name)
```


### `mutate_node`

Modifies metadata fields on all nodes, or scoped to a subset using the `where` argument:

```t
-- Mark all nodes as noop
p |> mutate_node($noop = true)

-- Mark only R nodes as noop (useful for skipping heavy computations)
p |> mutate_node($noop = true, where = $runtime == "R")

-- Override serializer for all nodes
p |> mutate_node($serializer = "pmml", where = $runtime == "R")
```

Mutable metadata fields: `noop` (Bool), `runtime` (String), `serializer` (String), `deserializer` (String).

### `rename_node`

Renames a single node and automatically rewires all dependency edges that referenced the old name. This is the canonical way to resolve name collisions before set operations like `union`.

```t
p = pipeline { a = 1; b = a + 1 }

p2 = p |> rename_node("a", "alpha")
pipeline_nodes(p2)   -- ["alpha", "b"]
pipeline_deps(p2)    -- {`alpha`: [], `b`: ["alpha"]}
```

Attempting to rename to a name that already exists is an error:

```t
p |> rename_node("a", "b")
-- Error(ValueError: "A node named `b` already exists in the Pipeline.")
```

### `arrange_node`

Returns a new pipeline with nodes sorted by a metadata field. This affects only display/serialization order — the DAG determines execution order.

---

## 23. Pipeline Manipulation for Data Scientists

Beyond basic execution, T allows you to treat a Pipeline as a queryable and mutable data structure. This is powerful for meta-programming, automated reporting, and "surgical" updates to large analysis graphs.

### Finding Errored Nodes Programmatically
In a production setting, you may want to extract the errors from a failed pipeline run to log them or send an alert.

```t
p = build_pipeline(p)

-- Get detailed records for all failed nodes
failed_records = errored_nodes(p)

-- Extract just the names and error messages
errors = map(failed_records, \(n) [name: n.name, msg: n.diagnostics.error])
```

### Filtering Subgraphs
If you have a massive pipeline but only want to visualize or re-run a specific subset (e.g., all Python nodes), use `filter_node()`:

```t
-- Create a subgraph of only Python-based computations
py_pipeline = p |> filter_node($runtime == "Python")

-- Create a subgraph of 'shallow' nodes (roots and their immediate children)
shallow_p = p |> filter_node($depth <= 1)
```

### Surgical Reconfiguration
Lenses allow you to modify a pipeline specification without using the `pipeline { ... }` block again. This is useful for "what-if" analysis or dynamic configuration.

```t
-- 1. Identify a node to skip
noop_l = node_meta_lens("heavy_computation", "noop")

-- 2. Toggle the noop flag surgically
p_fast = p |> set(noop_l, true)

-- 3. Swap a runtime for testing
p_test = p |> set(node_meta_lens("model_train", "runtime"), "R")
```

### Inspecting Node Results with Lenses
If you have a `VPipeline` object (from `read_pipeline()`), you can use lenses to safely extract values from specific nodes.

```t
p_info = read_pipeline(p)

-- Focus on the 'summary' node's value
summary_l = node_lens("summary")
summary_df = get(p_info, summary_l)
```

```t
p = pipeline { z = 1; a = 2; m = 3 }

p |> arrange_node($name) |> pipeline_nodes       -- ["a", "m", "z"]
p |> arrange_node($name, "desc") |> pipeline_nodes -- ["z", "m", "a"]

-- Sort a chain by depth (shallowest first)
p = pipeline { a = 1; b = a + 1; c = b + 1 }
p |> arrange_node($depth) |> pipeline_nodes      -- ["a", "b", "c"]
```

---

## 23. Set Operations

Pipelines can be treated as named sets of nodes. T provides four set operations that combine or subtract pipelines.

> **Immutability**: All set operations return new Pipelines. The original pipelines are never modified.
>
> **Lazy validation**: Set operations do not check DAG validity. If the result has dangling references, errors surface at `build_pipeline` or `pipeline_run` time.

### `union`

Merges two pipelines, including all nodes from both. Errors immediately on any name collision. Use `rename_node` to resolve collisions first.

```t
p_etl = pipeline {
  raw   = read_csv("data.csv")
  clean = raw |> filter($value > 0)
}

p_model = pipeline {
  fit    = lm(clean, formula = y ~ x)
  report = summary(fit)
}

p_full = p_etl |> union(p_model)
pipeline_nodes(p_full)  -- ["raw", "clean", "fit", "report"]
```

If both pipelines have a node named `clean`:

```t
p_etl |> union(p_model)
-- Error(ValueError: "Function `union`: name collision(s) detected: clean. Use `rename_node` to resolve.")

-- Fix: rename before merging
p_model2 = p_model |> rename_node("clean", "clean_model")
p_etl |> union(p_model2)
```

---

## 24. Diagnostic Suppression

Nodes that produce large numbers of non-terminal warnings (like those from `filter()` or complex modeling functions) can be silenced using the `suppress_warnings` combinator. This silences the console output for a node while maintaining the warning records for auditability.

```t
p = pipeline {
  -- High-noise node with suppressed warnings
  filtered = dataframe([[x: 1], [x: NA], [x: 3]]) 
    |> filter($x > 1) 
    |> suppress_warnings

  -- Downstream node remains unaffected
  count = nrow(filtered)
}
```

When building or running a pipeline with suppressed nodes, the summary reflects this state:

```
Pipeline summary: 1 node(s) with warnings, 1 suppressed, 0 error(s)
  ○  filtered — warnings suppressed by caller (1 NAs ignored)
```

The `○` symbol indicates a suppressed node. You can still access the underlying warning objects programmatically via `read_node()` or `read_pipeline()`.

```t
res = read_node(p, "filtered")
res.diagnostics.warnings_suppressed  -- true
res.diagnostics.warnings            -- list of captured warnings
```

### `difference`

Removes from the first pipeline all nodes whose names appear in the second pipeline. Nodes in the second pipeline that don't exist in the first are silently ignored.

```t
p = pipeline { a = 1; b = 2; c = 3; d = 4 }
p_remove = pipeline { b = 0; d = 0 }

p |> difference(p_remove) |> pipeline_nodes  -- ["a", "c"]
```

### `intersect`

Retains only nodes present by name in both pipelines, using definitions from the first pipeline.

```t
p1 = pipeline { a = 1; b = 2; c = 3 }
p2 = pipeline { b = 99; c = 100; d = 4 }

p1 |> intersect(p2) |> pipeline_nodes  -- ["b", "c"] (p1's definitions)
```

### `patch`

Like `union`, but only updates nodes that already exist in the first pipeline — it will not add new nodes from the second pipeline. Ideal for overriding configurations without accidentally importing stray nodes.

```t
p_prod = pipeline {
  load  = read_csv("data.csv")
  model = rn(command = <{ lm(y ~ x, data = load) }>, serializer = "pmml")
}

p_overrides = pipeline {
  model = rn(command = <{ lm(y ~ x + z, data = load) }>, serializer = "pmml")
  extra = 99  -- stray node
}

p_updated = p_prod |> patch(p_overrides)
pipeline_nodes(p_updated)  -- ["load", "model"] — "extra" was not added
```

---

## 24. DAG-Aware Transformations

These operations are structurally aware of the pipeline's dependency graph and are used to replace node implementations, reroute edges, and extract subgraphs.

### `swap`

Replaces a node's implementation while preserving its existing dependency edges. The new node is specified as the third argument.

```t
p = pipeline {
  data  = read_csv("data.csv")
  model = rn(command = <{ lm(y ~ x, data = data) }>, serializer = "pmml")
  score = node(command = predict(model, data), deserializer = "pmml")
}

-- Replace the model node with a new implementation; edges to/from model are preserved
new_model = rn(command = <{ glm(y ~ x, data = data, family = binomial) }>, serializer = "pmml")
p2 = p |> swap("model", new_model)

pipeline_deps(p2)
-- `model` still depends on `data`, and `score` still depends on `model`
```

### `rewire`

Reroutes a node's declared dependencies. The `replace` argument maps old dependency names to new ones. Only the named node's dependency list is updated.

```t
p = pipeline {
  data    = read_csv("data.csv")
  data_v2 = read_csv("data_v2.csv")
  model   = rn(command = <{ lm(y ~ x, data) }>, serializer = "pmml")
}

-- Re-point model to use data_v2 instead of data
p2 = p |> rewire("model", replace = list(data = "data_v2"))
pipeline_deps(p2)
-- {`data`: [], `data_v2`: [], `model`: ["data_v2"]}
```

### `prune`

Removes all leaf nodes — nodes that nothing else depends on. This is useful for cleaning up intermediate pipelines after `filter_node` or `difference` operations that may leave orphaned utility nodes.

```t
p = pipeline { a = 1; b = a + 1; c = 3 }
-- `a` is depended on by `b`, so it is not a leaf.
-- `b` depends on `a` but nothing depends on `b` — it is a leaf.
-- `c` is independent and nothing depends on it — it is also a leaf.

p |> prune |> pipeline_nodes  -- ["a"] (both b and c are leaves, removed)
```

You can chain `difference` and `prune` to strip unwanted branches in one step:

```t
p_partial = p |> difference(p_debug_nodes) |> prune
```

### `upstream_of`

Returns a new pipeline containing the named node and all its transitive ancestors (everything the node depends on, directly or indirectly).

```t
p = pipeline {
  raw     = read_csv("data.csv")
  clean   = raw |> filter($value > 0)
  model   = rn(command = <{ lm(y ~ x, clean) }>, serializer = "pmml")
  report  = summary(model)
  sidebar = "metadata"
}

-- Everything needed to produce `model`
p |> upstream_of("model") |> pipeline_nodes  -- ["raw", "clean", "model"]
-- sidebar is excluded because model doesn't depend on it
```

### `downstream_of`

Returns a new pipeline containing the named node and all nodes that transitively depend on it (everything that uses this node, directly or indirectly).

```t
-- Everything that is affected if `clean` changes
p |> downstream_of("clean") |> pipeline_nodes  -- ["clean", "model", "report"]
-- raw and sidebar are excluded
```

### `subgraph`

Returns the full connected component of a node — the union of its ancestors and descendants.

```t
p = pipeline { a = 1; b = a + 1; c = b + 1; d = 99 }

-- Everything connected to b (upstream and downstream)
p |> subgraph("b") |> pipeline_nodes  -- ["a", "b", "c"] — d is disconnected
```

---

## 25. Pipeline Composition

These higher-level operators combine two complete, separately-defined pipelines into one.

### `chain`

Connects two pipelines where the second pipeline's nodes reference node names from the first as dependencies. T verifies that at least one such shared reference exists; if the two pipelines are completely disconnected, `chain` raises an error.

```t
p_etl = pipeline {
  raw   = read_csv("data.csv")
  clean = raw |> filter($value > 0)
}

-- p_model references `clean` from p_etl — this is the wire
p_model = pipeline {
  fit    = lm(clean, formula = y ~ x)
  report = summary(fit)
}

p_full = p_etl |> chain(p_model)
pipeline_nodes(p_full)  -- ["raw", "clean", "fit", "report"]
```

`chain` is stricter than `union`: it requires an *intent* to connect the pipelines, catching accidental merges where no wiring was meant.

### Cross-Pipeline Dependency Tracking: T vs. RawCode

T's dependency tracking works differently depending on the node's runtime. This leads to a specific limitation when using `chain()` with R or Python pipelines.

#### How T Detects Dependencies
- **T Expressions**: T has a full understanding of its own syntax. When you use a variable that isn't defined inside the pipeline (and isn't in your global environment), T knows for certain it is an external dependency.
- **RawCode (<{ ... }>)**: For R and Python, T uses a fast **lexical heuristic** (scanning for words) to find dependencies. It cannot reliably distinguish between a foreign function (like `lm()`) and a T variable from a different pipeline.

#### The Limitation
To avoid polluting your build environment with R/Python functions as Nix dependencies, T **ignores** external references inside RawCode blocks when they are not defined in the current pipeline block.

**This means `chain()` will fail to automatically wire R/Python nodes to nodes in other pipelines.**

#### The Solution: The T-Stub Workaround
If you need an R or Python node to depend on a node from a separate pipeline via `chain()`, you must "bring" that dependency into the pipeline block using a T-expression stub with an **aliased name**.

**❌ Broken: R node cannot "see" `raw_data` for chaining**
```t
p_data = pipeline { raw_data = read_csv("data.csv") }

p_model = pipeline {
  model = rn(<{ 
    lm(mpg ~ hp, data = raw_data) 
  }>)
}

-- Error: "no shared dependency names found"
p_full = p_data |> chain(p_model)
```

**❌ Also broken: self-referential stub**
```t
p_model = pipeline {
  raw_data = raw_data  -- Error: "Self-referential node detected"
  model = rn(<{ lm(mpg ~ hp, data = raw_data) }>)
}
```

**✅ Fixed: Use a T-stub with an aliased name**
```t
p_data = pipeline { raw_data = read_csv("data.csv") }

p_model = pipeline {
  -- Aliased T-stub: different name on the left, raw_data on the right.
  -- T can parse the RHS and see `raw_data` as an external dependency.
  data_input = raw_data
  
  model = rn(<{ 
    lm(mpg ~ hp, data = data_input)  -- use the alias name in R
  }>,
  deserializer = "arrow")
}

-- Success! T sees `raw_data` as a dependency of `data_input`, wiring the pipelines.
p_full = p_data |> chain(p_model)
```

By giving the stub a different name (`data_input = raw_data`), you avoid a self-reference while still creating a T-expression that references `raw_data`. T can parse the right-hand side, detect the cross-pipeline dependency, and allow `chain()` to wire the pipelines together. Note that R/Python code inside the chained node should use the **alias name** (`data_input`) as the variable, not the original (`raw_data`).

---

## 26. Parallel Execution

Combines two pipelines that are intended to run independently. No dependency wiring is performed. Errors on name collision.

```t
p_r_model = pipeline {
  r_fit = rn(command = <{ lm(y ~ x, data) }>, serializer = "pmml")
}

p_py_model = pipeline {
  py_fit = pyn(
    command = <{
      from sklearn.linear_model import LinearRegression
      LinearRegression().fit(X, y)
    }>,
    serializer = "pmml"
  )
}

-- Both models will run independently
p_both = parallel(p_r_model, p_py_model)
pipeline_nodes(p_both)  -- ["r_fit", "py_fit"]
```

---

## 27. Extended Inspection API

Beyond `pipeline_nodes` and `pipeline_deps`, T provides a complete structural inspection surface for pipelines.

### Boundary Nodes

```t
p = pipeline { a = 1; b = a + 1; c = b + 1 }

pipeline_roots(p)   -- ["a"]  — nodes with no dependencies
pipeline_leaves(p)  -- ["c"]  — nodes nothing depends on
```

### Dependency Edges

`pipeline_edges` returns a list of `[from, to]` pairs representing every edge in the DAG:

```t
p = pipeline { a = 1; b = a + 1; c = b + 1 }

pipeline_edges(p)  -- [["a", "b"], ["b", "c"]]
```

This is useful for serializing the graph structure or feeding it to external tools.

### Topological Depth

`pipeline_depth` returns the maximum topological depth across all nodes (root nodes have depth 0):

```t
p = pipeline { a = 1; b = a + 1; c = b + 1 }

pipeline_depth(p)  -- 2
```

### Cycle Detection

`pipeline_cycles` returns any node names involved in dependency cycles. A correctly formed pipeline always returns an empty list:

```t
p = pipeline { a = 1; b = a + 1 }
pipeline_cycles(p)  -- []
```

### `pipeline_print`

Prints a human-readable summary of all nodes to stdout, including their runtime, depth, noop status, and dependency list:

```t
p = pipeline {
  a = 1
  b = node(command = <{ 2 }>, runtime = R, serializer = "pmml")
  c = b + 1
}

pipeline_print(p)
-- Pipeline (3 nodes):
--   a                     runtime=T         depth=0  noop=false  deps=[]
--   b                     runtime=R         depth=0  noop=false  deps=[]
--   c                     runtime=T         depth=1  noop=false  deps=[b]
```

### `pipeline_dot`

Exports the pipeline as a [Graphviz](https://graphviz.org/) DOT string for visualization:

```t
p = pipeline { a = 1; b = a + 1; c = b + 1 }

dot = pipeline_dot(p)
print(dot)
-- digraph pipeline {
--   rankdir=LR;
--   node [shape=box];
--   "a" [label="a\n[T]"];
--   "b" [label="b\n[T]"];
--   "c" [label="c\n[T]"];
--   "a" -> "b";
--   "b" -> "c";
-- }
```

Pipe the output to `dot -Tpng` or paste it into https://dreampuf.github.io/GraphvizOnline/ to render a visual dependency graph.

---

## 28. Pipeline Validation

By design, T uses **lazy validation**: structural errors (missing dependencies, cycles) surface at `build_pipeline` or `pipeline_run` time, not at operation time. This allows you to compose and transform pipelines freely.

When you want to validate eagerly, T provides opt-in validation utilities.

### `pipeline_validate`

Returns a list of validation error messages. An empty list means the pipeline is structurally valid. This function **never throws** — it reports problems as data.

```t
p_good = pipeline { a = 1; b = a + 1 }
pipeline_validate(p_good)  -- []

-- Build a broken pipeline manually via difference
p_broken = pipeline { a = 1; b = a + 1 } |> filter_node($name == "b")
-- b now depends on a, but a was filtered out

pipeline_validate(p_broken)
-- ["Node `b` depends on `a` which does not exist in the pipeline."]
```

Checks performed:
1. All referenced dependencies exist as nodes in the pipeline.
2. No dependency cycles.

### `pipeline_assert`

Like `pipeline_validate`, but **throws** the first error found instead of returning a list. Returns the pipeline unchanged if valid. This is useful as a guard at a pipeline's construction site.

```t
p = pipeline { a = 1; b = a + 1 }
  |> filter_node($depth == 0)    -- keeps a only
  |> pipeline_assert              -- succeeds, returns the pipeline

-- Chaining validation into a construction expression:
safe_pipeline = pipeline { a = 1; b = a + 1 }
  |> mutate_node($noop = true, where = $runtime == "R")
  |> pipeline_assert
```

If validation fails:

```t
p_broken |> pipeline_assert
-- Error(ValueError: "Node `b` depends on `a` which does not exist in the pipeline.")
```

---

## 29. Handling Ambiguous Dependencies

T-Lang uses a lexical analyzer to automatically detect dependencies between nodes by scanning the code for variable names that match other node names. While this is convenient, there are cases where automatic detection is insufficient or may produce false positives.

### Excluding False Positives

Sometimes, a node's code may contain a word that matches another node name but is intended to be a comment or a string, not a dependency. To prevent these from causing unwanted dependency cycles, T automatically **strips standard comments** starting with `--` or `#` within foreign code blocks (`<{ ... }>`) before analyzing the code.

```t
p = pipeline {
  data = read_csv("input.csv")
  
  -- The analyzer will IGNORE the string 'results' because it's in a comment.
  -- This prevents an accidental dependency on the 'results' node.
  process = pyn(command = <{
    # We will save the processed results to a file
    import pandas as pd
    df = data.dropna()
    df
  }>)

  results = node(command = process |> head)
}
```

### Forcing Detection with `deps`

In some runtimes, like `sh` (shell), T cannot always reliably infer dependencies from the command string. Similarly, you may want to explicitly declare a dependency that isn't directly referenced in the code (e.g., a file produced by another node that your script reads via a hardcoded path).

For these cases, you can use the `deps` argument in node definitions to manually declare one or more dependencies:

```t
p = pipeline {
  raw_file = shn(command = <{ curl -o data.csv https://example.com/data.csv }>)

  -- This shell node reads data.csv, which is created by raw_file.
  -- We use the `deps` argument to ensure raw_file executes first.
  summary = shn(
    command = <{ cat data.csv | wc -l }>, 
    deps = [raw_file],
    serializer = "text"
  )
}
```

**Key Features of `deps`**:
- **First-Class Syntax**: `deps` is an optional argument available in `node()`, `rn()`, `pyn()`, and `shn()`.
- **Bare Identifiers**: You can list direct node names as bare identifiers (e.g., `deps = [node1, node2]`).
- **Manual Override**: It ensures the specified nodes are added to the dependency graph even if they aren't parsed from the command or script body.
- **Strict Validation**: T validates that all listed dependencies exist within the same pipeline.

---

## Best Practices

1. **Name nodes descriptively**: Use names like `raw_data`, `filtered_sales`, `summary_stats`
2. **Keep nodes focused**: Each node should do one thing
3. **Use pipes within nodes**: Combine pipeline structure with pipe operator for readability
4. **Inspect before consuming**: Use `pipeline_nodes()`, `pipeline_deps()`, and `pipeline_to_frame()` to understand pipeline structure
5. **Build incrementally**: Start with data loading, add transformations one node at a time
6. **Validate at construction time**: Use `pipeline_assert` at the end of a construction chain to catch structural errors early
7. **Compose with `chain` over `union`**: When two pipelines are intentionally connected, `chain` makes the dependency explicit; use `union` only when combining truly independent pipelines
8. **Use `filter_node` + `upstream_of` for partial builds**: Trim a large pipeline to just what you need before calling `build_pipeline`
9. **Resolve collisions with `rename_node` before set ops**: Both `union` and `chain` enforce unique names; rename conflicting nodes before merging

---

## Complete Example

```t
-- A full data analysis pipeline
p = pipeline {
  -- Load data
  raw = read_csv("employees.csv")
  
  -- Filter to active engineers
  engineers = raw
    |> filter($dept == "eng")
    |> filter($active == true)
  
  -- Compute statistics
  avg_salary = engineers.salary |> mean
  salary_sd = engineers.salary |> sd
  team_size = engineers |> nrow
  
  -- Sort by performance
  ranked = engineers |> arrange("score", "desc")
}

-- Access results
p.team_size     -- number of active engineers
p.avg_salary    -- mean salary
p.ranked        -- DataFrame sorted by score
```

---

## 39. Cross-Node Artifact Retrieval

When nodes are executed within a Nix-managed sandbox (via `populate_pipeline(p, build = true)`), they are isolated from each other. However, T provides a built-in mechanism for nodes to access the serialized artifacts of their dependencies.

### Automatic Environment Propagation

For every dependency `dep` that a node has, the pipeline runner automatically injects an environment variable named `T_NODE_<dep>` into the sandbox. This variable contains the path to the Nix store directory where that dependency's artifact is stored.

### Retrieval with `node_lens`

The canonical way to access a sibling node's artifact is using the `node_lens` with the single-argument `get()` function. This is preferred over manual environment variable lookup because:
1. It is **portable**: T handles the path resolution and deserialization automatically.
2. It is **integrated**: It uses the same deserializer system as the rest of the pipeline.

```t
p = pipeline {
  node_a = node(command = 100, serializer = "json")
  
  -- This node retrieves node_a's value from its Nix artifact
  dynamic_access = node(
    command = {
        -- Using get(node_lens("...")) for cross-node access
        val = get(node_lens("node_a"))
        val * 2
    },
    runtime = "T"
  )
}
```

When `dynamic_access` runs inside the Nix sandbox:
1. T sees the `node_lens("node_a")` and looks for the `T_NODE_node_a` environment variable.
2. It locates the `artifact` file within that path.
3. It detects the artifact class (e.g., `Int` from JSON) and deserializes it back into a T value.

This pattern is essential for **polyglot pipelines** where data is passed between T, R, and Python nodes through files, and for **dynamic access** nodes where the target of a retrieval is determined at runtime (e.g., `target = "A"; get(node_lens(target))`).

---

## Next Steps

Now that you've mastered pipelines, learn how to manage reproducible projects and develop T packages:

1. **[Project Development](project_development.md)** — Master T's project structure and dependency management.
2. **[Package Development](package_development.md)** — Create reusable T libraries.
3. **[Reproducibility Guide](reproducibility.md)** — Deep dive into T's commitment to reproducible research.
4. **[API Reference](api-reference.md)** — Complete function reference by package.


# FILE: docs/architecture.md

# T Language Architecture

Internal design and implementation of the T programming language.

## Table of Contents

- [Overview](#overview)
- [Language Pipeline](#language-pipeline)
- [Core Components](#core-components)
- [Type System](#type-system)
- [Execution Model](#execution-model)
- [Multi-Language Execution](#multi-language-execution)
- [Arrow Backend](#arrow-backend)
- [Package System](#package-system)
- [Design Decisions](#design-decisions)

---

## Overview

T is a tree-walking interpreter built in OCaml. The architecture prioritizes:

1. **Simplicity**: Straightforward implementation easy to understand and modify
2. **Correctness**: Explicit semantics with no hidden behavior
3. **Reproducibility**: Deterministic execution and Nix-managed dependencies
4. **Extensibility**: Modular package system for adding functionality

**Tech Stack:**
- **Host Language**: OCaml 4.14+
- **Parser Generator**: Menhir (LR parser)
- **Lexer**: ocamllex
- **Build System**: Dune
- **Data Backend**: Apache Arrow C GLib (via FFI)
- **Package Manager**: Nix

---

## Language Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                     Source Code (.t file)                    │
└─────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ LEXER (lexer.mll)                                            │
│ • Tokenizes input (IDENT, INT, FLOAT, STRING, keywords)     │
│ • Handles operators (|>, ?|>, ~)                             │
│ • Supports multiline pipes                                   │
└─────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ PARSER (parser.mly)                                          │
│ • Builds AST from token stream                               │
│ • Operator precedence (prec/assoc directives)                │
│ • NSE for DataFrame verbs                                    │
│ • Formula syntax (y ~ x)                                     │
└─────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ AST (ast.ml)                                                 │
│ • expr type: represents all expressions                      │
│ • value type: runtime values                                 │
│ • Includes types for errors, NA, pipelines, intents          │
└─────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ EVALUATOR (eval.ml)                                          │
│ • Tree-walking interpreter                                   │
│ • Environment-based variable lookup                          │
│ • Closures capture enclosing environment                     │
│ • Conditional pipe short-circuits on errors                  │
└─────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ STANDARD LIBRARY (packages/)                                 │
│ • One file per function                                      │
│ • Mix of T (.t) and OCaml (.ml) implementations              │
│ • Auto-loaded at startup                                     │
└─────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ ARROW BACKEND (arrow/)                                       │
│ • FFI to Arrow C GLib                                        │
│ • Columnar storage for DataFrames                            │
│ • Zero-copy column access                                    │
│ • Vectorized compute kernels                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. Lexer (`src/lexer.mll`)

**Purpose**: Convert source text into tokens.

**Key Features**:
- Keyword recognition (`if`, `else`, `function`, `pipeline`, etc.)
- Operators: arithmetic (`+`, `-`, `*`, `/`), comparison (`==`, `<`, `>`), logical (`and`, `or`, `not`)
- Pipe operators: `|>`, `?|>`, `~` (formula)
- Multiline support: Pipes can span multiple lines
- String literals with escape sequences
- Comments: `--` to end of line

**Example**:
```t
df |> filter($age > 30)
```

Tokens:
```
IDENT("df") PIPE IDENT("filter") LPAREN LAMBDA ...
```

### 2. Parser (`src/parser.mly`)

**Purpose**: Build abstract syntax tree (AST) from tokens.

**Grammar Highlights**:
- Expression-oriented: Everything is an expression (conditionals, blocks, etc.)
- Operator precedence: `*` / `/` bind tighter than `+` / `-`
- Pipe associativity: Left-associative (`a |> f |> g` = `(a |> f) |> g`)
- List comprehensions: `[expr for x in xs if pred]`
- Named arguments: `f(a = 1, b = 2)`

**Precedence** (low to high):
1. `|>`, `?|>` (pipes)
2. `or`
3. `and`
4. `not`
5. `==`, `!=`, `<`, `>`, `<=`, `>=`
6. `+`, `-`
7. `*`, `/`, `%`
8. Unary `-`
9. Function application

**Special Constructs**:
- **Pipelines**: `pipeline { node1 = expr1; node2 = expr2 }`
- **Intents**: `intent { field: value }`
- **Formulas**: `response ~ predictor`
- **Lambdas**: `\(x) expr` or `function(x) expr`

### 3. AST (`src/ast.ml`)

**Purpose**: Define data structures for the abstract syntax tree and runtime values.

**Key Types**:

```ocaml
(* Expression AST *)
type expr =
  | Int of int
  | Float of float
  | Bool of bool
  | String of string
  | Ident of string
  | List of expr list
  | Dict of (string * expr) list
  | Lambda of string list * expr
  | App of expr * expr list  (* Function application *)
  | BinOp of binop * expr * expr
  | UnOp of unop * expr
  | If of expr * expr * expr
  | Let of string * expr
  | Pipe of expr * expr  (* |> *)
  | MaybePipe of expr * expr  (* ?|> *)
  | Pipeline of (string * expr) list
  | Intent of (string * expr) list
  | Formula of expr * expr  (* y ~ x *)
  | ListComp of expr * string * expr * expr option
  (* ... *)

(* Runtime Values *)
type value =
  | VInt of int
  | VFloat of float
  | VBool of bool
  | VString of string
  | VList of value list
  | VDict of (string, value) Hashtbl.t
  | VFunction of string list * expr * environment
  | VDataFrame of dataframe
  | VVector of vector
  | VNA of na_type
  | VError of error_info
  | VPipeline of pipeline_data
  | VIntent of intent_data
  (* ... *)
```

**Design Notes**:
- Expressions are immutable; evaluation produces new values
- Functions capture environment as closures
- Errors and NA are first-class values, not exceptions
- DataFrames hold Arrow table handles (or fallback lists)

### 4. Evaluator (`src/eval.ml`)

**Purpose**: Execute AST nodes and produce values.

**Execution Strategy**: Tree-walking interpreter with environment-based variable lookup.

**Key Functions**:

```ocaml
(* Main evaluation function *)
val eval : environment -> expr -> value

(* Apply function to arguments *)
val apply_function : value -> value list -> value

(* Built-in operator evaluation *)
val eval_binop : binop -> value -> value -> value
val eval_unop : unop -> value -> value
```

**Environment Model**:
- Environments are hash tables: `string -> value`
- Nested scopes: Functions create child environments
- Closures: Functions capture their defining environment
- Immutability: Variables can't be reassigned (shadowing allowed)

**Pipe Evaluation**:

```ocaml
(* Conditional pipe |> *)
match eval env left with
| VError _ as err -> err  (* Short-circuit *)
| value -> apply_function (eval env right) [value]

(* Maybe-pipe ?|> *)
let value = eval env left in
apply_function (eval env right) [value]  (* Always forward *)
```

**Error Handling**:
- Errors are `VError` values, not OCaml exceptions
- Propagate through pipelines (unless caught)
- Actionable error messages with context

### 5. REPL (`src/repl.ml`)

**Purpose**: Interactive read-eval-print loop.

**Features**:
- Persistent environment across evaluations
- Pretty-printing of results
- Multiline input support
- Error recovery (don't crash on errors)
- Standard library auto-loaded at startup

**Flow**:
```
1. Read input
2. Lex & parse → AST
3. Evaluate → value
4. Pretty-print value
5. Update environment (for assignments)
6. Loop
```

---

## Type System

T is **dynamically typed** with runtime type checking.

### Value Types

| Type | OCaml Representation | Description |
|------|---------------------|-------------|
| `Int` | `VInt of int` | OCaml native int (63-bit on 64-bit systems) |
| `Float` | `VFloat of float` | OCaml float (IEEE 754 double) |
| `Bool` | `VBool of bool` | OCaml bool |
| `String` | `VString of string` | OCaml string |
| `List` | `VList of value list` | Heterogeneous lists |
| `Dict` | `VDict of (string, value) Hashtbl.t` | Mutable hash table |
| `Function` | `VFunction of params * body * env` | Closure |
| `DataFrame` | `VDataFrame of dataframe` | Arrow table or fallback |
| `Vector` | `VVector of vector` | Typed array (Int/Float/Bool/String) |
| `NA` | `VNA of na_type` | Typed missing value |
| `Error` | `VError of error_info` | Error with code, message, context |

### Type Checking

**Runtime Dispatch**: Functions check argument types at call time.

Example (addition):
```ocaml
match (left, right) with
| (VInt a, VInt b) -> VInt (a + b)
| (VFloat a, VFloat b) -> VFloat (a +. b)
| (VInt a, VFloat b) -> VFloat (float_of_int a +. b)
| (VFloat a, VInt b) -> VFloat (a +. float_of_int b)
| _ -> type_error "Cannot add {type1} and {type2}"
```

**No Static Types**: T does not have a static type system. All type errors are discovered at runtime.

---

## Execution Model

### Variable Binding

```t
x = 42
```

Evaluates the right-hand side, binds result to `x` in the current environment.

**Immutability**: Once bound, `x` cannot be reassigned. Shadowing in nested scopes is allowed:

```t
x = 1
let_block = {
  x = 2  -- Shadows outer x
  x + 10  -- 12
}
x  -- Still 1
```

### Function Application

```t
f = \(a, b) a + b
f(3, 5)  -- 8
```

1. Evaluate function expression → `VFunction(["a", "b"], body, env)`
2. Evaluate arguments → `[VInt 3, VInt 5]`
3. Create new environment extending function's captured environment
4. Bind parameters: `a → 3`, `b → 5`
5. Evaluate body in new environment → `VInt 8`

### Closures

Functions capture their defining environment:

```t
make_adder = \(n) \(x) x + n
add10 = make_adder(10)
add10(5)  -- 15
```

The inner lambda `\(x) x + n` captures the environment where `n = 10`.

### Pipeline Execution

Pipelines are DAGs of named computations:

```t
p = pipeline {
  x = 10
  y = 20
  sum = x + y
}
```

**Execution**:
1. Parse nodes → `[("x", Int 10), ("y", Int 20), ("sum", BinOp(Add, Ident "x", Ident "y"))]`
2. Topological sort (dependency order): `x`, `y`, `sum`
3. Evaluate each node, binding results: `x → 10`, `y → 20`, `sum → 30`
4. Store in `VPipeline` with results table
5. Access via `p.sum` → `30`

**Cycle Detection**: Circular dependencies produce an error:
```t
pipeline { a = b; b = a }  -- Error: Circular dependency
```

## Multi-Language Execution

T leverages Nix to orchestrate computation across multiple runtimes. When a node is configured with `runtime = "R"` or `runtime = "Python"`, the following architecture is used:

1. **Isolation**: Each node runs in a dedicated Nix derivation with its own language environment.
2. **Environment Injection**: Project dependencies from `tproject.toml` are automatically satisfied in the sandbox.
3. **Data Interchange**:
   - **DataFrames**: Passed via Apache Arrow IPC for zero-copy performance.
   - **Models**: Passed via PMML (Predictive Model Markup Language) for high-fidelity cross-language persistence.
   - **Scalars**: Passed via JSON or T's native binary format.
4. **Code Injection**: T automatically injects a bridge layer into the R/Python scripts to handle reading dependencies and writing the node result using the specified serializer.

For direct user-facing Arrow file workflows outside pipelines, T also exposes:

- `read_arrow(path)` for Arrow IPC input
- `write_arrow(dataframe, path)` for Arrow IPC output

That means Arrow is used both as an internal storage backend and as an interchange format at the language boundary.

### Handling Foreign Objects & Robustness

T puts significant effort into providing high-fidelity representations of Python, R, and Julia objects. 

- **Fail-Safe Loading**: The `read_node()` function is designed to never crash the primary T environment, even if the node's artifacts are missing or corrupted. 
- **Representation Wrappers**: T provides specialized "host object" representations for common foreign types (Lists, Dicts, DataFrames, Models). If a node produces an object that T doesn't natively understand, it is safely wrapped as a generic `HostObject` that can still be passed as a reference to other nodes of the same language (e.g., from one R node to another) without T needing to understand its internal structure.
- **Native Fallback**: If T's representation is insufficient for a particular task, users can always access the raw object by reading the node's artifact directly from within a native script (e.g., using `read_node()` inside a `.qmd` or `.py` component). This ensures full interop with the entire ecosystem of libraries in those languages.


---

## Arrow Backend

T uses **Apache Arrow** for high-performance columnar data.

### Architecture

```
┌─────────────────────┐
│ T DataFrame Value   │
│ (VDataFrame)        │
└──────────┬──────────┘
           │
           ↓
┌─────────────────────┐      ┌──────────────────────┐
│ Native Arrow Handle │ OR   │ Fallback (OCaml list)│
│ (arrow::Table*)     │      │ List of rows/columns │
└──────────┬──────────┘      └──────────────────────┘
           │
           ↓
┌─────────────────────────────────────────┐
│ Arrow C GLib FFI (src/arrow/)           │
│ • garrow_table_new_from_csv()           │
│ • garrow_table_get_column()             │
│ • garrow_array_get_value()              │
│ • garrow_compute_*() kernels            │
└─────────────────────────────────────────┘
           │
           ↓
┌─────────────────────────────────────────┐
│ Apache Arrow C++ (libarrow.so)          │
│ • Columnar storage                       │
│ • SIMD-accelerated compute               │
│ • Zero-copy slicing                      │
└─────────────────────────────────────────┘
```

### FFI Bindings

Located in `src/arrow/`:
- **arrow_ffi.ml**: OCaml wrappers for C functions
- **C stubs**: Interface to Arrow C GLib

**Examples**:
```ocaml
external read_csv_native : string -> arrow_table = "caml_arrow_read_csv"
external read_ipc_native : string -> arrow_table = "caml_arrow_read_ipc"
```

The repository currently exposes both a backend-native CSV reader and Arrow IPC read/write support. The public `read_csv()` builtin still layers OCaml CSV parsing on top of Arrow-backed table construction, while `read_arrow` / `write_arrow` expose Arrow IPC directly.

### Dual-Path Operations

Every DataFrame operation has two paths:

1. **Native Arrow Path** (when `native_handle` is available):
   - Use Arrow Compute kernels via FFI
   - Zero-copy operations
   - Vectorized SIMD execution
   - Arrow IPC round-trips preserve the native storage model well

2. **Fallback Path** (when no native handle):
   - Pure OCaml implementation
   - Works on converted list-of-records
   - Slower but always available
   - Still produces correct user-visible behavior when a schema cannot stay native

**Example** (`filter` operation):
```ocaml
match df.native_handle with
| Some handle ->
    (* Use Arrow filter kernel via FFI *)
    arrow_compute_filter handle predicate
| None ->
    (* Fallback: OCaml list filter *)
    List.filter predicate df.rows
```

### Column Access

```t
df.age
```

Returns a `VVector`:
- If native handle: Zero-copy view into Arrow column
- If fallback: Extracted OCaml list

---

## Package System

Standard library functions are organized into packages.

### Structure

```
src/packages/
├── base/          # Errors, NA, assertions
├── core/          # Functional utilities
├── math/          # Mathematical functions
├── stats/         # Statistical functions
├── dataframe/     # CSV I/O, DataFrame ops
├── colcraft/      # Data verbs, window functions
├── pipeline/      # Pipeline introspection
└── explain/       # Debugging tools
```

**One File Per Function**: Each function lives in its own file (e.g., `mean.ml`, `filter.ml`).

### Implementation Options

1. **OCaml (`.ml`)**: Performance-critical or complex logic
   ```ocaml
   (* src/packages/stats/mean.ml *)
   let mean values na_rm =
     (* Implementation *)
   ```

2. **T (`.t`)**: Simple functions defined in T itself
   ```t
   -- src/packages/core/double.t
   double = \(x) x * 2
   ```

### Auto-Loading

All packages are loaded at REPL/script startup:

```ocaml
(* In repl.ml or main.ml *)
let initial_env = Environment.create () in
Package_loader.load_all_packages initial_env
```

Functions are registered in the global environment by name.

---

## Design Decisions

### Why Tree-Walking Interpreter?

**Pros**:
- Simple to implement and modify
- Direct AST representation
- Easy debugging
- Fast development iteration

**Cons**:
- Slower than bytecode or JIT
- No ahead-of-time optimization

**Decision**: For alpha, simplicity and correctness outweigh raw performance. Future versions may add bytecode compilation.

### Why OCaml?

**Pros**:
- Excellent parser/compiler tooling (Menhir, ocamllex)
- Strong type system for host language (prevents bugs)
- Good FFI story (C bindings for Arrow)
- Fast native compilation
- Functional paradigm matches T's design

**Cons**:
- Smaller ecosystem than Python/JavaScript
- Steeper learning curve for contributors

**Decision**: OCaml's strengths in language implementation outweigh ecosystem concerns.

### Why Apache Arrow?

**Pros**:
- Industry-standard columnar format
- Zero-copy interoperability (Parquet, R, Python, Julia)
- High-performance compute kernels
- Cross-language support

**Cons**:
- Large dependency
- C++ dependency management complexity (mitigated by Nix)
- FFI maintenance burden

**Decision**: Arrow's performance and interoperability are critical for data analysis. Nix ensures reproducible builds.

### Why Nix?

**Pros**:
- Perfect reproducibility (same inputs → same outputs)
- Declarative dependency management
- Isolated development environments
- Cross-platform consistency

**Cons**:
- Steep learning curve
- Longer initial build times
- Smaller user base than Docker

**Decision**: Reproducibility is a core value; Nix is the best tool for this goal.

### Why Explicit NA Handling?

**Pros**:
- No silent data loss
- Forces user to think about missingness
- Predictable behavior

**Cons**:
- More verbose than automatic propagation
- Requires `na_rm` parameters everywhere

**Decision**: Explicit beats implicit. R's silent NA propagation leads to subtle bugs; T forces intentionality.

### Why No Static Types?

**Pros**:
- Faster prototyping
- Simpler user experience (no type annotations)
- Easier REPL workflow

**Cons**:
- Runtime errors instead of compile-time errors
- Less safety for large codebases

**Decision**: For alpha, dynamic typing matches T's exploratory, REPL-first workflow. Static typing may be added in future versions as an optional layer.

---

## Performance Characteristics

### Asymptotic Complexity

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| Variable lookup | O(1) | Hash table |
| Function call | O(n) params | Environment copy |
| List access | O(n) | Linked list |
| DataFrame filter (native) | O(n) | Arrow kernel |
| DataFrame filter (fallback) | O(n) | OCaml iteration |
| Pipeline topological sort | O(V + E) | DAG traversal |

### Memory Model

- **Values**: Immutable, shared via references
- **DataFrames**: Arrow columnar storage (shared buffers)
- **Closures**: Capture full environment (can be large)

### Bottlenecks

1. **Function calls**: Environment copying is expensive
2. **Fallback DataFrame ops**: Pure OCaml slower than Arrow
3. **List operations**: Linked lists have poor cache locality

### Optimization Opportunities

- Bytecode compilation
- JIT for hot paths
- Persistent data structures (fewer copies)
- Lazy evaluation for pipelines
- Arrow Compute for more operations

---

## Testing Strategy

### Test Types

1. **Unit Tests**: OCaml functions in `tests/`
2. **Golden Tests**: Compare T output against R (in `tests/`)
3. **Example Tests**: Runnable examples in `examples/`
4. **Property Tests**: QuickCheck-style (future)

### Golden Test Workflow

```bash
# Run T program
dune exec src/repl.exe < tests/mean_test.t > t_output.txt

# Run equivalent R script
Rscript tests/mean_test.R > r_output.txt

# Compare
diff t_output.txt r_output.txt
```

### Testing Philosophy

- **Correctness over coverage**: Focus on semantics, not LOC coverage
- **Cross-validation**: Compare against established tools (R, Python)
- **Real-world data**: Use actual CSV files, not just synthetic data

---

## Future Architecture Directions

### Bytecode Compilation

Replace tree-walking interpreter with bytecode VM:
- Compile AST → bytecode
- Stack-based VM for execution
- Faster loops and function calls

### Type Inference

Add optional static typing:
- Hindley-Milner type inference
- Gradual typing (mix static/dynamic)
- IDE support via Language Server Protocol

### Distributed Execution

Pipeline nodes run on clusters:
- Serialize pipelines to remote workers
- Arrow Flight for zero-copy data transfer
- Fault tolerance via re-execution

### GPU Acceleration

Arrow Compute on CUDA:
- Offload aggregations to GPU
- Vectorized operations on GPU
- Requires cuDF or similar

---

## Next Steps

Now that you understand T's internal architecture, explore the full API or learn how to contribute to the project:

1. **[API Reference](api-reference.md)** — Exhaustive guide to T's standard library.
2. **[Contributing Guide](contributing.md)** — Learn how to contribute to T development.
3. **[Development Guide](development.md)** — Technical details for setting up a local build.
4. **[Reproducibility Guide](reproducibility.md)** — T's commitment to reproducible research.


# FILE: docs/error-handling.md

# Error Handling in T

Comprehensive guide to error handling, recovery patterns, and debugging in T.

## Table of Contents

- [Error Philosophy](#error-philosophy)
- [Error Types](#error-types)
- [Error as Values](#error-as-values)
- [Pipe Operators and Errors](#pipe-operators-and-errors)
- [Pattern Matching and Errors](#pattern-matching-and-errors)
- [Error Recovery Patterns](#error-recovery-patterns)
- [Pipeline Diagnostics and Soft-Failures](#pipeline-diagnostics-and-soft-failures)
- [Polyglot Error Handling (Python/R)](#polyglot-error-handling-pythonr)
- [Common Errors](#common-errors)
- [Best Practices](#best-practices)

---

## Error Philosophy

T treats errors as **first-class values**, not exceptions. This design enables:

1. **Explicit Error Handling**: Errors don't crash programs; they flow through pipelines
2. **Railway-Oriented Programming**: Success and failure paths are explicit
3. **Composable Recovery**: Error handling logic can be pipelined like data
4. **Predictable Behavior**: No hidden control flow from exceptions
5. **Observability at Scale**: Pipeline builds capture and persist errors as artifacts, preventing build halts while ensuring full traceability.

**Key Principle**: Errors are data, and data can be transformed, inspected, and recovered from.

---

## Execution Modes: Resilient vs. Fail-Fast

T-Lang provides two modes of evaluation, controlled by the "resilience" setting:

### 1. Resilient Mode (Default)
Evaluation continues even when statements or pipeline nodes result in `VError` values. This is aligned with the "Errors are Values" philosophy, allowing you to collect as much information as possible from a single run. Residual errors are simply passed to downstream functions (which may short-circuit via `|>` or recover via `?|>`). This is the recommended mode for complex data pipelines where you want to observe as many diagnostic outcomes as possible in a single pass.

### 2. Fail-Fast Mode
Evaluation stops immediately upon encountering the first `VError`. This is the usual, common behaviour for critical scripts where subsequent steps should only run if previous ones were flawlessly successful.

**How to toggle**:
- **CLI**: Use `t run --failfast script.t`
- **REPL**: Set `t_run(failfast = true, ...)`
- **Pipelines**: Use `t_make(failfast = true)`

---

---

## Error Types

T has several categories of errors:

### 1. Type Errors

Occur when operations receive incompatible types:

```t
1 + "hello"
-- Error(TypeError: Cannot add Int and String)

[1, 2] * 3
-- Error(TypeError: Cannot multiply List and Int. Hint: Use map(\(x) x * 3))
```

### 2. Name Errors

Occur when referencing undefined variables or functions:

```t
undefined_var
-- Error(NameError: 'undefined_var' is not defined)

prnt(42)
-- Error(NameError: 'prnt' is not defined. Did you mean 'print'?)
```

**Features**:
- Levenshtein distance-based suggestions
- Searches current scope and standard library
- Case-insensitive suggestions

### 3. Value Errors

Occur when values are invalid for the operation:

```t
sqrt(-1)
-- Error(ValueError: Cannot compute square root of negative number)

quantile([1, 2, 3], 1.5)
-- Error(ValueError: Quantile must be between 0 and 1)
```

### 4. Arity Errors

Occur when function calls have wrong number of arguments:

```t
add = \(a, b) a + b
add(1)
-- Error(ArityError: Expected 2 arguments (a, b) but got 1)

add(1, 2, 3)
-- Error(ArityError: Expected 2 arguments (a, b) but got 3)
```

**Features**:
- Shows expected parameter names
- Shows actual argument count
- Suggests correct usage

### 5. Division by Zero

```t
1 / 0
-- Error(DivisionByZero: Division by zero)

10 % 0
-- Error(DivisionByZero: Modulo by zero)
```

### 6. NA Errors

Occur when NA values are encountered without explicit handling:

```t
mean([1, NA, 3])
-- Error(NAError: NA value encountered. Use na_rm = true to skip NA values)

1 + NA
-- Error(TypeError: Operation on NA value)
```

### 7. Assertion Errors

Occur when assertions fail:

```t
assert(2 + 2 == 5)
-- Error(AssertionError: Assertion failed)

assert(false, "Custom message")
-- Error(AssertionError: Custom message)
```

### 8. Validation Errors

Custom errors for data validation:

```t
validate_age = \(age) 
  if (age < 0 or age > 150)
    error("ValidationError", "Age must be between 0 and 150")
  else
    age

validate_age(-5)
-- Error(ValidationError: Age must be between 0 and 150)
```

---

## Error as Values

### Creating Errors

```t
-- Generic error
err = error("Something went wrong")

-- Error with code
err = error("NotFoundError", "File not found")

-- Conditional errors
result = if (value < 0)
  error("ValueError", "Value must be positive")
else
  value
```

### Inspecting Errors

```t
result = 1 / 0

-- Check if error
is_error(result)        -- true

-- Get error code
error_code(result)      -- "DivisionByZero"

-- Get error message
error_message(result)   -- "Division by zero"

-- Get additional context
error_context(result)   -- Stack trace or additional info
```

### Error Propagation

Errors flow through computations until caught:

```t
step1 = 1 / 0                    -- Error
step2 = step1 + 10               -- Still error (no computation)
step3 = step2 * 2                -- Still error

is_error(step3)                  -- true
error_message(step3)             -- "Division by zero"
```

---

## Pipe Operators and Errors

### Conditional Pipe (`|>`)

**Short-circuits** on errors:

```t
-- Success path
5 |> \(x) x * 2 |> \(x) x + 1   -- 11

-- Error short-circuits
error("fail") |> \(x) x * 2 |> \(x) x + 1
-- Error(GenericError: fail)
-- The functions are never called
```

**Use case**: Normal data pipelines where errors should stop processing.

```t
df = read_csv("data.csv")
  |> filter($age > 0)
  |> select($name, $age)
  |> arrange($age)
-- If read_csv fails, rest of pipeline is skipped
```

### Maybe-Pipe (`?|>`)

**Always forwards** values, including errors:

```t
-- Success path (same as |>)
5 ?|> \(x) x * 2                 -- 10

-- Error is forwarded to function
error("fail") ?|> \(x) 
  if (is_error(x)) 0 else x      -- 0 (recovered!)
```

**Use case**: Error recovery, fallback values, logging.

```t
-- Recovery pattern
result = risky_operation()
  ?|> \(x) if (is_error(x)) {
    print(str_join(["Error occurred: ", error_message(x)]))
    default_value
  } else {
    x
  }

-- Chain recovery with normal processing
error("fail")
  ?|> \(x) if (is_error(x)) 0 else x  -- Recovery
  |> \(x) x + 1                        -- Normal processing (1)
```

---

## Pattern Matching and Errors

Pattern matching is the most declarative way to handle first-class errors in T. It allows you to destructure error values and branch logic based on specific outcomes.

### Basic Error Matching

Use the `Error { msg }` pattern to capture the error message:

```t
result = match(1 / 0) {
  Error { msg: m } => str_sprintf("Caught error: %s", m),
  val => str_sprintf("Result: %f", val)
}
-- "Caught error: Division by zero"
```

### Automatic Error Propagation

If you don't explicitly handle `Error` in a `match` expression, the original error value is propagated automatically. This matches the behavior of the standard pipe (`|>`).

```t
-- This match does NOT handle Error
res = match(error("Fail")) {
  [head, ..tail] => head,
  [] => 0
}
-- Result is still Error("Fail")
```

---

## Error Recovery Patterns

### Pattern 1: Default Values

```t
-- Return default on error using match
safe_divide = \(a, b)
  match(a / b) {
    Error { _ } => 0.0,
    res => res
  }

safe_divide(10, 0)   -- 0.0
safe_divide(10, 2)   -- 5.0
```

### Pattern 2: Fallback Sources

```t
-- Try multiple data sources cleanly
data = match(read_csv("primary.csv")) {
  Error { _ } => match(read_csv("backup.csv")) {
    Error { _ } => read_csv("fallback.csv"),
    res => res
  },
  res => res
}

-- Or combining match with the maybe-pipe for flat recovery
final_data = read_csv("primary.csv")
  ?|> \(res) match(res) {
    Error { _ } => read_csv("backup.csv"),
    valid_df => valid_df
  }
```

### Pattern 3: Validation and Recovery

```t
-- Validate, recover if invalid
process_value = \(v)
  if (v < 0)
    error("ValueError", "Negative value")
  else if (is_na(v))
    error("NAError", "NA value")
  else
    v * 2

-- Recover from validation errors
safe_process = \(v)
  process_value(v) ?|> \(result)
    if (is_error(result)) {
      print(str_sprintf("Invalid value: %s", error_message(result)))
      0  -- Default
    } else {
      result
    }

safe_process(-5)   -- Prints error, returns 0
safe_process(10)   -- Returns 20
```

### Pattern 4: Error Logging

```t
-- Log errors and continue
logged_operation = risky_function()
  ?|> \(x) if (is_error(x)) {
    write_log(str_sprintf("Error in risky_function: %s", error_message(x)))
    x  -- Pass error along
  } else {
    x
  }

-- Or convert to success after logging
logged_with_default = logged_operation
  ?|> \(x) if (is_error(x)) default_value else x
```

### Pattern 5: Partial Success

```t
-- Process list, collecting errors
process_many = \(items)
  map(items, \(item)
    process_item(item) ?|> \(result)
      if (is_error(result))
        {success: false, error: error_message(result)}
      else
        {success: true, value: result}
  )

results = process_many([1, -2, 3, 0])
-- [
--   {success: true, value: 2},
--   {success: false, error: "Negative value"},
--   {success: true, value: 6},
--   {success: false, error: "Division by zero"}
-- ]

-- Filter successes
successes = filter(results, \(r) r.success)
```

### Pattern 6: Error Transformation

Pattern matching is excellent for converting low-level errors into domain-specific ones.

```t
-- Transform errors using match
enhance_error = \(e)
  match(e) {
    Error { msg } => 
      if (str_detect(msg, "DivisionByZero"))
        error("MathError", str_sprintf("Calculation failed: %s", msg))
      else if (str_detect(msg, "NAError"))
        error("DataQualityError", str_sprintf("Quality issue: %s", msg))
      else
        e,
    _ => e
  }

risky_calc() ?|> enhance_error
```

---

## Pipeline Diagnostics and Soft-Failures

In T-Lang, the materialization of a pipeline is a separate phase from the logic execution. When a node in a pipeline fails, it doesn't necessarily halt the entire build.

### Hard-Fail vs. Soft-Fail

1.  **Hard-Fail**: Occurs when the environment or system fails (e.g., missing dependencies, Nix build errors, out-of-memory). The build stops immediately and no artifacts are produced.
2.  **Soft-Fail (Captured Error)**: Occurs when the node's internal code (T, Python, or R) raises an error. The node produces a `VError` artifact instead of the expected data. The pipeline build **continues**, allowing other independent branches to complete.

### The Build Summary

After a build, T provides an iconographic summary:

```text
✖ Pipeline build captured node errors [5 succeeded, 2 captured errors, 2 had warnings]
  ! Captured error in node: r_err
  ! Captured error in node: py_err
  ? Warnings in node: r_warn
  ? Warnings in node: py_warn
```

- **`!` (Captured error)**: The node failed, producing a `VError` artifact.
- **`?` (Warnings)**: The node succeeded, but issued non-terminal diagnostics.

### Investigating with `explain()`

When you load a node that soft-failed, you receive a T-Lang Error object. You can use the `explain()` builtin to see the exact cause, including tracebacks from other languages.

```t
hu = read_node("py_err")
-- Error(RuntimeError: "Critical error in Python logic")

explain(hu)
-- Output:
-- Context:
--   runtime_traceback: "Traceback (most recent call last): ..."
--   node_name: "py_err"
--   node_status: "errored"
```

---

## Polyglot Error Handling (Python/R)

T-Lang provides a "diagnostic bridge" for nodes running in other languages.

### Python Nodes
- **Exceptions**: All uncaught exceptions are caught by the T-Lang runner. The exception type, message, and full traceback are serialized into the `VError` artifact.
- **Warnings**: Captured via `warnings.catch_warnings()`. These are listed in the build summary but do not cause the node to return an error state.

### R Nodes
- **Errors**: Handled via `tryCatch`. R conditions are mapped to `VError` codes.
- **Warnings**: Handled via `withCallingHandlers`. Warnings are collected into the node's metadata without interrupting the primary data export.

---

### Pattern 7: Conditional Modeling and Automated Reporting

In automated daily pipelines where data is refreshed externally, a three-way branching strategy is often necessary. You can use pattern matching to choose between a full complex model, a simplified fallback model, or a validation report based on the data's characteristics.

```t
p = pipeline {
  -- 1. Load the latest daily raw data
  raw_data = node(command = read_csv("daily_extract.csv"))

  -- 2. Validate and "tag" the data based on quality metrics
  quality_status = node(command = 
    raw_data ?|> \(df) {
      if (nrow(df) < 500) 
        error("CriticalError", "Insufficient rows for any modeling.")
      else if (length(levels(df.segment)) < 2)
        [type: "low_diversity", data: df]
      else
        [type: "high_quality", data: df]
    }
  )

  -- 3. Precise branching: Choose the best action for each state
  final_result = node(command = 
    quality_status ?|> \(outcome) match(outcome) {
      -- Full Case: Sufficient data and factor levels
      [type: "high_quality", data: df] => 
        lm(df, $yield ~ $temp + $segment),
      
      -- Fallback Case: Enough data, but not enough factor diversity
      -- We drop the 'segment' predictor to avoid model failure
      [type: "low_diversity", data: df] => 
        lm(df, $yield ~ $temp),
      
      -- Failure Case: Stop modeling and generate a diagnostic report
      Error { msg } => 
        generate_validation_report(msg, raw_data)
    }
  )
}
```

**Why use this?**:
*   **Adaptive Modeling**: Your pipeline automatically scales its complexity to match the quality of the incoming data, avoiding "singular matrix" or "one level factor" errors.
*   **Operational Intelligence**: Instead of the whole pipeline failing due to a minor data shift (like one category disappearing from today's extract), the system gracefully degrades its service while still providing a result.
*   **Auditability**: Every run clearly states which path was taken through the use of descriptive tags like `low_diversity` or `high_quality`.

---

## Comparing Error Handling Tools

T offers several tools for managing errors, each suited for different scenarios:

*   **Conditional Pipe (`|>`)**: Best for "fail-fast" pipelines where any error should immediately stop further processing. It's the default for sequential operations.
*   **Maybe-Pipe (`?|>`)**: Ideal for scenarios requiring explicit error handling or recovery at each step. It allows functions to receive and act upon error values, enabling logging, fallback logic, or transformation.
*   **Pattern Matching (`match`)**: The most declarative and powerful tool for branching logic based on error types or success values. It's excellent for:
    *   **Specific Error Recovery**: Handling different error types differently.
    *   **Default Values/Fallbacks**: Providing alternative values when an error occurs.
    *   **Error Transformation**: Converting generic errors into more domain-specific ones.
    *   **Complex Recovery Logic**: When `if (is_error(x))` becomes too nested or less readable.

**General Guidance**:
*   Use `|>` for the majority of your data pipelines where you expect success and want to stop on the first error.
*   Use `?|>` when you need to inspect or act on an error *at a specific point* in a pipeline, often followed by `match` or an `if (is_error(...))` check.
*   Use `match` when your error recovery logic involves different actions for different error types, or when you want a clear, declarative way to distinguish between success and various error states.

---

## Common Errors

### NA Handling Errors

**Problem**: Forgot to handle NA values

```t
mean([1, 2, NA, 4])
-- Error(NAError: NA value encountered)
```

**Solution**: Use `na_rm = true`

```t
mean([1, 2, NA, 4], na_rm = true)  -- 2.33...
```

### Type Mismatch Errors

**Problem**: Mixing incompatible types

```t
"Age: " + 25
-- Error(TypeError: Cannot add String and Int)
```

**Solution**: Use separate print statements (alpha does not have string conversion yet)

```t
-- Workaround for output:
print("Age: ")
print(25)

-- Or use R/Python for formatting if needed
```

### Empty Collection Errors

**Problem**: Operating on empty data

```t
mean([])
-- Error(ValueError: Cannot compute mean of empty list)
```

**Solution**: Check before operating

```t
safe_mean = \(data)
  if (length(data) == 0)
    error("ValueError", "Empty data")
  else
    mean(data)

-- Or use default
safe_mean_with_default = \(data)
  if (length(data) == 0) 0.0 else mean(data)
```

### Division by Zero

**Problem**: Dividing by zero

```t
revenue_per_customer = total_revenue / customer_count
-- Error if customer_count = 0
```

**Solution**: Guard condition

```t
revenue_per_customer = if (customer_count == 0)
  0.0
else
  total_revenue / customer_count
```

### Missing Column Errors

**Problem**: Referencing non-existent column

```t
df.nonexistent_column
-- Error(NameError: Column 'nonexistent_column' not found)
```

**Solution**: Check columns first

```t
cols = colnames(df)
has_column = length(filter(cols, \(c) c == "age")) > 0

if (has_column)
  df.age
else
  error("ColumnError", "Required column 'age' not found")
```

---

## Best Practices

### 1. Fail Fast, Fail Explicitly

**Good**: Validate inputs early

```t
process_data = \(df)
  if (nrow(df) == 0)
    error("ValidationError", "Empty dataset")
  else if (not has_required_columns(df))
    error("ValidationError", "Missing required columns")
  else
    -- Process data
```

**Bad**: Silent failures

```t
process_data = \(df)
  -- Assumes data is valid, may fail later
  df |> filter(...) |> summarize(...)
```

### 2. Use Descriptive Error Messages

**Good**: Clear, actionable messages

```t
if (age < 0 or age > 150)
  error("ValidationError", str_sprintf("Age must be between 0 and 150, got: %s", str_string(age)))
```

**Bad**: Vague messages

```t
if (age < 0 or age > 150)
  error("Invalid age")
```

### 3. Choose the Right Pipe

**Use `|>`** for normal success paths:
```t
df |> filter($active) |> select($name)
```

**Use `?|>`** for error recovery:
```t
load_data() ?|> \(x) if (is_error(x)) backup_data() else x
```

### 4. Document Error Conditions

```t
-- Computes mean, errors if list is empty or contains NA
-- Use na_rm = true to skip NA values
my_mean = \(values, na_rm)
  if (length(values) == 0)
    error("ValueError", "Empty list")
  else
    -- Implementation
```

### 5. Test Error Cases

```t
-- Test successful case
assert(safe_divide(10, 2) == 5.0)

-- Test error recovery
assert(safe_divide(10, 0) == 0.0)
assert(is_error(risky_function(-1)))
```

### 6. Log Errors in Production

```t
production_pipeline = pipeline {
  data = read_csv("data.csv") ?|> \(x) if (is_error(x)) {
    write_log(str_sprintf("CRITICAL: Failed to load data: %s", error_message(x)))
    x
  } else x
  
  -- Rest of pipeline with error handling
}
```

### 7. Avoid Deep Nesting

**Bad**: Deeply nested error checks

```t
result = if (is_error(step1))
  handle_step1_error(step1)
else
  if (is_error(step2))
    handle_step2_error(step2)
  else
    if (is_error(step3))
      handle_step3_error(step3)
    else
      success_value
```

**Good**: Use maybe-pipe for flat composition

```t
result = step1
  ?|> \(x) if (is_error(x)) handle_step1_error(x) else step2(x)
  ?|> \(x) if (is_error(x)) handle_step2_error(x) else step3(x)
  ?|> \(x) if (is_error(x)) handle_step3_error(x) else x
```

---

## Debugging Errors

### Print Error Details

```t
result = risky_operation()

if (is_error(result)) {
  print(str_sprintf("Error code: %s", error_code(result)))
  print(str_sprintf("Error message: %s", error_message(result)))
  print(str_sprintf("Error context: %s", error_context(result)))
}
```

### Trace Error Source

```t
-- Add markers in pipeline
step1 = operation1() ?|> \(x) if (is_error(x)) {
  print("Error at step1")
  x
} else x

step2 = operation2(step1) ?|> \(x) if (is_error(x)) {
  print("Error at step2")
  x
} else x
```

### Assert Invariants

```t
-- Use assertions to catch logic errors
result = computation()
assert(result > 0, "Result should be positive")
assert(length(result_list) == expected_length, "Length mismatch")
```

---

**See Also**:
- [Examples](examples.md) — Error handling patterns in practice
- [API Reference](api-reference.md) — Error-related functions
- [Troubleshooting](troubleshooting.md) — Common issues and solutions


# FILE: docs/reproducibility.md

# Reproducibility in T

How T ensures perfect reproducibility for data analysis through Nix integration and deterministic execution.

## The Reproducibility Problem

Traditional data science faces a reproducibility crisis:

- **Dependency Drift**: Package versions change over time
- **Platform Differences**: Code behaves differently on Linux vs macOS vs Windows
- **Hidden State**: Random seeds, global variables, system time
- **Implicit Assumptions**: Undocumented data preprocessing steps

**Result**: "Works on my machine" syndrome — analyses that can't be reproduced months or years later.

---

## T's Reproducibility Guarantee

T provides **perfect reproducibility**: The same T code with the same data produces identical results, always.

### Three Pillars

1. **Nix Package Management**: Frozen dependency versions
2. **Deterministic Execution**: No hidden randomness or state
3. **Intent Blocks**: Document assumptions and constraints

---

## Nix Integration

### What is Nix?

Nix is a declarative package manager that ensures:
- **Bit-for-bit identical builds** across machines
- **Isolated environments** (no global state)
- **Versioned dependencies** (pinned to exact commits)

### How T Uses Nix

Every T project is a **Nix flake**:

**`flake.nix`**:
```nix
{
  description = "My T analysis project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    tlang.url = "github:b-rodrigues/tlang/v0.51.4";
  };

  outputs = { self, nixpkgs, tlang }: {
    devShell = nixpkgs.lib.mkShell {
      buildInputs = [
        tlang.packages.${system}.default
        # Any other dependencies
      ];
    };
  };
}
```

**Lock file** (`flake.lock`): Pins exact versions

```json
{
  "nodes": {
    "tlang": {
      "locked": {
        "narHash": "sha256-...",
        "rev": "abc123...",
        "type": "github"
      }
    }
  }
}
```

### Reproducibility Across Time

**Scenario**: You run an analysis today. A colleague tries to run it in 2026.

**Without Nix**:
- Package versions have changed
- APIs have breaking changes
- Results differ or code errors

**With Nix**:
```bash
# 2026: Same exact environment as 2024
nix develop github:myuser/my-analysis?rev=abc123
t run src/pipeline.t

# Identical output, guaranteed
```

The `flake.lock` file ensures every dependency (OCaml, Arrow, system libraries) is pinned to the exact version used originally.

---

## Deterministic Execution

### No Hidden Randomness

T has **no built-in randomness**:
- No random number generators (RNG)
- No random seeds
- No sampling without explicit seed

**To add randomness** (future feature):
```t
-- Explicit, reproducible randomness
rng = random_seed(12345)
sample = random_sample(data, 100, rng)
```

### No Implicit State

- **No global variables**: All state is explicit in pipelines
- **No system time**: Computations don't depend on clock
- **No file system side effects** (except explicit I/O)

### Deterministic Pipelines

Pipelines execute in **topological order** (determined by dependencies):

```t
p = pipeline {
  z = x + y
  x = 10
  y = 20
}
-- Always executes: x, y, then z
-- Order of declaration doesn't matter
```

**Same inputs → Same outputs**, always.

---

## Documenting Assumptions with Intent Blocks

Intent blocks make **implicit knowledge explicit**:

```t
intent {
  description: "Customer churn prediction for Q4 2023",
  
  data_source: "customers.csv from Salesforce export 2023-12-31",
  
  assumptions: [
    "Churn defined as no purchase in 90 days",
    "Test accounts excluded (account_type != 'test')",
    "Incomplete records removed (age, email must be present)"
  ],
  
  constraints: [
    "Age between 18 and 100",
    "Email format validated",
    "Purchase amounts > 0"
  ],
  
  preprocessing: [
    "Column names cleaned (snake_case)",
    "NA values in 'income' imputed with median",
    "Outliers beyond 3σ removed"
  ],
  
  environment: {
    t_version: "0.51.4",
    nix_revision: "abc123",
    run_date: "2024-01-15"
  }
}

-- Analysis code follows...
```

**Benefits**:
- Future readers understand context
- LLMs can regenerate code correctly
- Auditors can verify assumptions
- Changes to assumptions are versioned (Git)

---

## Reproducible Workflow Example

### Project Structure

```
my-analysis/
├── flake.nix           # Nix configuration
├── flake.lock          # Locked dependencies
├── data/
│   └── sales.csv       # Input data (or fetch script)
├── src/
│   └── pipeline.t      # T analysis script
├── outputs/
│   └── report.csv      # Generated results
└── README.md           # Documentation
```

### Step 1: Create Nix Flake

**`flake.nix`**:
```nix
{
  description = "Q4 2023 Sales Analysis";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    tlang.url = "github:b-rodrigues/tlang/v0.51.4";
  };
  
  outputs = { self, nixpkgs, tlang }: {
    # ... configuration ...
  };
}
```

### Step 2: Write Analysis with Intent

**`src/pipeline.t`**:
```t
intent {
  description: "Q4 2023 revenue analysis by region",
  data_source: "data/sales.csv (exported 2023-12-31)",
  assumptions: "All sales in USD, no refunds included",
  created: "2024-01-15",
  author: "Data Team"
}

sales = read_csv("data/sales.csv", clean_colnames = true)

analysis = pipeline {
  cleaned = sales
    |> filter($amount > 0)
    |> filter(not is_na($region))
  
  by_region = cleaned
    |> group_by($region)
    |> summarize($total_revenue = sum($amount))
    |> arrange($total_revenue, "desc")
}

write_csv(analysis.by_region, "outputs/report.csv")
```

### Step 3: Run Analysis

```bash
# Enter reproducible environment
nix develop

# Run analysis
t run src/pipeline.t

# Output: outputs/report.csv
```

### Step 4: Version Control

```bash
git init
git add flake.nix flake.lock src/ data/ README.md
git commit -m "Initial Q4 2023 analysis"
git tag v1.0.0
git push
```

### Step 5: Reproduce Anywhere

**On any machine, any time**:
```bash
# Clone project
git clone https://github.com/myorg/q4-analysis.git
cd q4-analysis

# Enter exact same environment
nix develop

# Run analysis
t run src/pipeline.t

# Verify identical output
diff outputs/report.csv expected_report.csv
# (No differences)
```

---

## Reproducibility Checklist

### For Every Analysis

- [ ] Use Nix flake with locked dependencies
- [ ] Add intent block documenting assumptions
- [ ] Explicit NA handling (`na_rm = true` where needed)
- [ ] No randomness without explicit seeds
- [ ] Version control everything (code + `flake.lock`)
- [ ] Document data sources and versions
- [ ] Test re-execution produces identical results

### For Sharing

- [ ] Include `flake.nix` and `flake.lock`
- [ ] Document data download/preparation steps
- [ ] Provide expected outputs for verification
- [ ] Include README with run instructions
- [ ] Tag releases with Git (`git tag v1.0.0`)

### For Long-Term Storage

- [ ] Archive with Zenodo or similar (DOI)
- [ ] Include all dependencies in archive
- [ ] Document minimum system requirements
- [ ] Provide checksum for verification

---

## Advanced Reproducibility

### Containerization

Nix + Docker for maximum portability:

```dockerfile
FROM nixos/nix

WORKDIR /analysis
COPY . .

RUN nix develop --command dune build

CMD ["nix", "develop", "--command", "t", "run", "src/pipeline.t"]
```

### Continuous Integration

Verify reproducibility on every commit:

**`.github/workflows/reproduce.yml`**:
```yaml
name: Verify Reproducibility

on: [push]

jobs:
  reproduce:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: cachix/install-nix-action@v15
      - run: nix develop --command t run src/pipeline.t
      - run: diff outputs/result.csv expected_result.csv
```

### Data Versioning

Use DVC or Git-LFS for data versioning:

```bash
# Track data files
dvc add data/sales.csv
git add data/sales.csv.dvc

# Data is versioned alongside code
```

---

## Reproducibility vs Performance

**Trade-off**: Perfect reproducibility sometimes costs performance.

**Strategies**:

1. **Cache expensive computations** (Nix store)
2. **Parallelize where deterministic** (map/reduce)
3. **Profile and optimize hot paths** (keep determinism)
4. **Document performance assumptions** (hardware, runtime)

**Example**:
```t
intent {
  performance: "Optimized for 8-core CPU, 16GB RAM",
  runtime_expected: "5 minutes on reference hardware",
  caching: "Pipeline nodes cached in .cache/"
}
```

---

## Reproducibility Best Practices

1. **Pin Everything**: Nix locks all dependencies
2. **Document Everything**: Intent blocks capture assumptions
3. **Test Everything**: Verify results are identical on re-run
4. **Version Everything**: Git for code, DVC for data
5. **Share Everything**: Public repos, archived datasets

---

## Next Steps

Now that you understand T's commitment to reproducibility, explore the language and its architecture:

1. **[Architecture](architecture.md)** — Understand the internal design and execution model of T.
2. **[Pipeline Tutorial](pipeline_tutorial.md)** — Build reproducible data pipelines.
3. **[Project Development](project_development.md)** — Master T's project structure and dependency management.
4. **[API Reference](api-reference.md)** — Complete function reference by package.


# FILE: docs/data_manipulation_examples.md

# Data Manipulation Examples

> Practical examples of data wrangling with T's core verbs

T provides a powerful suite of data manipulation functions in the `colcraft` package, inspired by `dplyr` and `tidyr`. These functions take a DataFrame as their first argument and return a new DataFrame, making them highly composable with the pipe operator.

---

## Loading Data

```t
df = read_csv("employees.csv")
-- DataFrame(100 rows x 5 cols: [name, age, score, dept, salary])

nrow(df)      -- 100
ncol(df)      -- 5
colnames(df)  -- ["name", "age", "score", "dept", "salary"]
```

### glimpse() — Inspect DataFrame Structure

Use `glimpse()` for a quick, tidy overview of a DataFrame's structure, dimensions, and contents:

```t
df |> glimpse()
-- # A DataFrame: 100 × 5
-- name   (String): "Alice", "Bob", "Charlie", ...
-- age    (Int): 30, 25, 42, ...
-- score  (Float): 88.5, 92.0, 75.2, ...
-- dept   (String): "eng", "eng", "sales", ...
-- salary (Float): 85000.0, 92000.0, 65000.0, ...
```

Unlike `print()`, which shows a formatted table, `glimpse()` lists columns vertically with their types and a sample of values, making it ideal for wide datasets or quick exploration.

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

### Combining Conditions

To combine multiple conditions in `filter()`, use the **logical** operators `&&` (AND) and `||` (OR):

```t
-- Engineering department AND age > 25
df |> filter($dept == "eng" && $age > 25)

-- Sales department OR high score
df |> filter($dept == "sales" || $score > 90)
```

> [!TIP]
> **No Silent Magic**: Standard bitwise operators `&` and `|` are strictly for scalars. If you accidentally use them in a filter (e.g., `$age > 25 & $dept == "eng"`), T will return a helpful `TypeError` suggesting the use of `&&`/`||` for combining filter conditions, or `.&`/`.|` for vectorized element-wise operations.

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

## Reshaping Data (tidyr)

T includes a robust implementation of tidying functions for reshaping your data.

### pivot_longer() — Lengthen Data

Pivots data from wide to long format by consolidating multiple columns into name-value pairs.

```t
-- Pivot age and score into a single "measure" column
df |> pivot_longer($age, $score, names_to = "measure", values_to = "val")

-- Resulting columns: name, dept, salary, measure, val
```

### pivot_wider() — Widen Data

Pivots data from long to wide format by spreading unique values across multiple columns.

```t
-- Widen by department names, using salary as values
df |> select($name, $dept, $salary)
   |> pivot_wider(names_from = $dept, values_from = $salary)
```

### separate() — Split Columns

Splits a single character column into multiple columns based on a delimiter.

```t
-- Split a "date" column into "year", "month", "day"
df |> separate($date, into = ["year", "month", "day"], sep = "-")
```

### unite() — Combine Columns

Combines multiple columns into a single character column.

```t
-- Combine year, month, day into a single "full_date" column
df |> unite("full_date", $year, $month, $day, sep = "-")
```

### nest() — Nest Columns into Sub-DataFrames

Groups data and packs selected columns into a single nested list-column containing DataFrames.

```t
-- Nest columns mpg and hp into a column named "data"
-- Other columns (cyl, etc.) remain as grouping keys
nt = df |> nest($mpg, $hp)

-- Use selection helpers to nest all columns starting with 's'
nt = df |> nest(data = starts_with("s"))

-- Automatic grouping behavior:
-- If already grouped, nest() without arguments nests all non-grouping columns.
nt = df |> group_by($cyl) |> nest()
-- Resulting schema: [cyl, data] where data contains all other columns
```

### unnest() — Expand Nested Columns

Expands a nested list-column back into regular rows and columns.

```t
-- Unnest the "data" column back into individual columns
df_flat = nt |> unnest($data)
```

---

## Missing Value Handling

### drop_na() — Remove NAs

Removes rows containing missing values in the specified columns.

```t
-- Remove rows where Ozone or Solar.R are NA
df |> drop_na($Ozone, $`Solar.R`) -- Dots in names require backticks
```

### replace_na() — Replace NAs

Replaces missing values with a specific constant for each column.

```t
-- Replace NAs in Ozone with 0
df |> replace_na([Ozone: 0, `Solar.R`: 0])
```

### fill() — Fill Gaps

Propagates non-missing values in a specific direction.

```t
-- Fill missing categories downwards
df |> fill($category, .direction = "down")
```

---

## Completing and Expanding Data

### complete() — Make Implicit Missing Values Explicit

Ensures all combinations of the specified columns exist in the data.

```t
-- Ensure every item has a row for every group
df |> complete($group, $item_id, fill = [value: 0])
```

### expand() — Generate All Combinations

Generates all unique combinations of variables found in a dataset.

```t
-- Every combination of type and size, regardless of whether it exists in df
df |> expand($type, $size)
```

### crossing() — Cartesian Product

Creates a new DataFrame from the cross-product of inputs.

```t
-- Independent of any existing DataFrame
crossing(x = [1, 2, 3], y = ["a", "b"])
```

### nesting() — Restrict Combinations

Used inside `expand()` or `complete()` to only include combinations already present in the data.

```t
-- Only combinations of type and size that actually appear in the data
df |> expand(nesting($type, $size))

-- In complete(): use nesting() to restrict some columns to existing combinations
df |> complete($group, nesting($item_id, $item_name))
```

---

## Factors — Categorical Variables

Create categorical data with defined levels. Factors respect their level order when sorting, rather than alphabetical order.

### factor() — Create a Factor

Creates a factor from a vector or column, optionally specifying levels.

```t
-- Create a factor from a vector
let f = factor(["low", "high", "medium"], levels = ["low", "medium", "high"])

-- Create a factor column using mutate
df |> mutate($size_fct = factor($size, levels = ["small", "medium", "large"]))
```

### as_factor() — Coerce to Factor

Coerces a column to a factor (categorical) value, deriving levels from the unique values present.

```t
df |> mutate($category = as_factor($category))
```

### fct_infreq() — Reorder Levels by Frequency

Reorders factor levels in descending order of frequency.

```t
df |> mutate($category = fct_infreq($category))
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

---

## Next Steps

Now that you've mastered the core data manipulation verbs, explore specialized data types and advanced modeling in T:

1. **[Handling Dates](handling_dates.md)** — Learn how to parse, manipulate, and format temporal data.
2. **[String Manipulation](string_manipulation.md)** — Explore powerful functions for text processing and regular expressions.
3. **[Factors](factors.md)** — Understand categorical variables and level management.
4. **[API Reference](api-reference.md)** — Explore the full set of functions available in T's standard library.


# FILE: docs/models.md

# Statistical Models & Tidy Output

> [!IMPORTANT]
> **Native Support Note**: $T$ provides native implementations for Linear Models (`lm`) and PMML-imported **Decision Trees** and **Random Forests**. For other advanced modeling (GLMs, Mixed Models, Machine Learning), $T$ uses a polyglot approach where models are trained in R or Python nodes and exchanged through PMML or ONNX.

$T$ treats models as first-class objects that can be summarized and evaluated regardless of which runtime created them.

## Fitting Models

### `lm()` — Linear Regression (Native)
Fits an Ordinary Least Squares (OLS) model. Following $T$'s "Data First" philosophy, the dataset is the first argument.

```t
-- Positional: data, then formula
model = lm(mtcars, mpg ~ wt + hp)

-- Named args also supported
model = lm(data = mtcars, formula = mpg ~ wt + hp)
```

### Advanced Modeling (Polyglot)
To fit models beyond simple OLS, use `R` or `Python` nodes within a $T$ pipeline. These nodes can serialize model artifacts through PMML or ONNX depending on the scoring path you want.

#### Example: Logistic Regression in R
```t
p = pipeline {
    model_node = rn(
        command = <{
            glm(Survived ~ Pclass + Sex + Age, data = titanic, family = binomial())
        }>,
        serializer = "pmml"
    )
}
build_pipeline(p)
model = read_node("model_node")
summary(model) -- Fully supported in T!
```

#### Example: Logistic Regression in Python via ONNX
```t
p = pipeline {
    model_node = pyn(
        command = <{
            from sklearn.linear_model import LogisticRegression
            clf = LogisticRegression().fit(X, y)
            clf
        }>,
        serializer = ^onnx
    )
}
build_pipeline(p)
model = read_node("model_node")
```

---

## Model Inspection & Diagnostics

> [!TIP]
> **Native Convenience**: All model inspection and diagnostic functions are implemented natively in $T$. This means that even if a model was originally trained in R or Python (and imported via PMML), you can perform summaries, calculate residuals, and run hypothesis tests **without** needing an active R or Python environment. This approach provides significant speed advantages and simplifies high-performance pipelines.

$T$ adopts the `broom` philosophy: model outputs should be DataFrames or Tidy Dictionaries.

### `summary(model)`
Returns a tidy representation of coefficients. 
* For native `lm`, it returns a DataFrame. 
* For some imported models, it returns a Dict where the tidy DataFrame is in `_tidy_df`.

```t
s = summary(model)
s._tidy_df
-- # A DataFrame: 3 × 5
--   term         estimate  std_error  statistic  p_value
```

### `coef(model)`
A convenience function that returns a two-column DataFrame with just `term` and `estimate`.

### `fit_stats(model)`
Returns a single-row DataFrame of model-level statistics (R-squared, AIC, BIC, etc.).
For PMML decision trees and random forests, this includes tree metadata such as `n_trees`, `n_features`, `model_type`, and `mining_function`.

```t
stats = fit_stats(model)
-- # A DataFrame: 1 × 15
--   r_squared  adj_r_squared  aic    bic    nobs
```

### `conf_int(model, level = 0.95)`
Computes confidence intervals for model coefficients.

```t
ci = conf_int(model, level: 0.99)
-- # A DataFrame: 3 × 3
--   term         lower     upper
```

### `compare(model1, model2, ...)`
Aligns multiple model coefficient tables into a single wide DataFrame for side-by-side comparison.

```t
comp = compare(m1, m2)
-- Returns DataFrame with columns: estimate_1, std_error_1, ..., estimate_2, ...
```

### `augment(data, model)`
Augments the original data with core model-based columns: `fitted`, `resid`, and `std_resid`.

```t
aug = augment(mtcars, model)
-- Adds columns: fitted, resid, std_resid
```

### `add_diagnostics(data, model)`
Similar to `augment`, but adds a more comprehensive set of diagnostic columns (leverage, influence, etc.).

```t
diag = add_diagnostics(mtcars, model)
-- Adds columns: fitted, resid, hat, sigma, cooksd, std_resid
```

### `residuals(data, model, type = "response")`
Returns a DataFrame containing the `actual` response, the `fitted` values, and the calculated `resid` (residuals).

```t
res = residuals(mtcars, model, type: "pearson")
-- # A DataFrame: 32 × 3 [actual, fitted, resid]
```

---

## Hypothesis Testing & Diagnostics

### `anova(model1, model2, ...)`
Performs Analysis of Variance (ANOVA) comparing two or more nested models.

```t
m1 = lm(mtcars, mpg ~ wt)
m2 = lm(mtcars, mpg ~ wt + hp + qsec)
av = anova(m1, m2)
-- Returns an ANOVA table with Statistics and P-values
```

### `wald_test(model, terms, value = 0.0)`
Performs a joint Wald test on a subset of model coefficients.

```t
-- Test if both 'hp' and 'qsec' are jointly equal to zero
w = wald_test(model, terms: ["hp", "qsec"])
```

### `vcov(model)`
Returns the Variance-Covariance matrix of the coefficients as a square DataFrame.

```t
v = vcov(model)
```

---

## Prediction

The `predict(data, model)` function performs vectorized predictions natively in $T$ for native, PMML-backed, and ONNX-backed models.

```t
-- Fast, native evaluation in T
-- Even if the model was trained in R or Python (and imported via PMML)
preds = predict(new_data, model)
```

$T$ supports various link functions for GLMs (imported via PMML), including **Logit**, **Probit**, **Log**, **Inverse**, and **Cloglog**.

> **PMML Trees & Boosting**: $T$ can now evaluate PMML-imported **Decision Trees**, **Random Forests**, and **XGBoost (GBTree)** models natively (no external runtime). This includes PMML exports from **scikit-learn** via `sklearn2pmml`. Use `t_read_pmml()` to load the model and `predict(df, model)` to score new data.

> **ONNX Native Inference**: $T$ can run ONNX models natively through ONNX Runtime using `t_read_onnx()` plus `predict(df, model)`. The current implementation supports single-input/single-output models and expects the selected numeric feature columns to match the model input width.

---

## Model Interchange: PMML and ONNX

### Why PMML?
The **Predictive Model Markup Language (PMML)** is the bridge between $T$ and other runtimes when you want T-native scoring. It allows:
1. **R Integration**: Using any R model that has a PMML exporter (e.g. `stats::glm`, `survival::coxph`).
2. **Python Integration**: Using `scikit-learn` or `statsmodels`.
3. **Reproducibility**: Models persist independently of the original runtime code.

### Why ONNX?
**ONNX** is the preferred interchange format when you want broad ML model coverage or faster native inference through ONNX Runtime. It allows:
1. **Python ML Export**: `scikit-learn` models via `skl2onnx`.
2. **Native T Loading**: Reading models with `t_read_onnx(path)` and scoring them with `predict(data, model)`.
3. **R/Python Runtime Loading**: Reading models via the `onnx` R package or Python `onnxruntime`.
4. **Broader Coverage**: Neural-network and non-PMML model families that PMML cannot represent well.

Use `^pmml` when you want T's hand-written classical-model evaluator. Use `^onnx` when you want a portable model artifact with native ONNX Runtime inference in T or cross-runtime execution in Python/R.

### Cross-Runtime Consistency
$T$'s statistical evaluator is verified against R's reference implementation. Results match R's `broom::tidy()` and `stats::predict()` exactly.

---

## Comparison with R's broom Package

| R (broom) / stats | T equivalent |
|-------------------|--------------|
| `broom::tidy(fit)` | `summary(model)` |
| `broom::glance(fit)` | `fit_stats(model)` |
| `broom::augment(fit, data)` | `augment(df, model)` |
| `stats::residuals(fit)` | `residuals(df, model)`|
| `stats::coef(fit)` | `coef(model)` |
| `stats::vcov(fit)` | `vcov(model)` |
| `stats::anova(m1, m2)` | `anova(m1, m2)` |
| `survey::regTermTest` | `wald_test(model, terms)` |

---

## Next Steps

Now that you can fit and inspect statistical models, explore how to build reproducible data pipelines and manage projects in T:

1. **[Pipeline Tutorial](pipeline_tutorial.md)** — Learn how to build reproducible, DAG-based data analysis workflows.
2. **[PMML Tutorial](pmml_tutorial.md)** — Learn the supported PMML workflows for moving models between R, Python, and T.
3. **[Project Development](project_development.md)** — Master T's project structure and dependency management.
4. **[Package Development](package_development.md)** — Create reusable T libraries.
5. **[API Reference](api-reference.md)** — Complete function reference by package.


# FILE: docs/arrow.md

# Arrow Ingestion Strategy

T prioritizes high-performance data ingestion by leveraging native Apache Arrow and Parquet readers. This document outlines how T handles different formats and its "Native-First" philosophy.

## Native-First CSV Ingestion

T uses a fast, native path for reading CSV files when they follow standard conventions. This path utilize the `GArrowCSVReader` from the Arrow C GLib library, which is significantly faster and more memory-efficient than pure OCaml parsers for large datasets.

### Native Path Activation

The native Arrow CSV reader is used automatically when calling `read_csv()` with its default parameters:
- Comma separator (`,`)
- No skipping of header or lines
- No automatic column name cleaning

If any non-default options are provided (e.g., `separator = ";"`, `skip_lines = 5`), T falls back to a pure OCaml CSV parser. This ensure full compatibility with complex CSV formats while providing maximum speed for standard ones.

### NULL Value Handling (NA)

The native reader is configured to recognize the following strings as `NA` (NA values):
- `NA`
- `na`
- `N/A`
- Empty fields

This ensures consistency between the native reader and the OCaml fallback parser.

## Parquet Support

T provides first-class support for Parquet files via `read_parquet()`. Parquet is the recommended format for large-scale data in T because:
- It is a binary, columnar format with built-in compression.
- Type information is preserved, avoiding the overhead of type inference.
- Native ingestion via `parquet-glib` is faster than CSV reading.
- It supports zero-copy loading of large datasets into memory.

## Technical Fallbacks

If the native Arrow reader fails for any reason (e.g., malformed file, unsupported encoding), T provides a robust fallback mechanism:

1. **Native Attempt**: Try reading using `GArrowCSVReader`.
2. **Warning**: If native reading fails, a warning is printed to stderr.
3. **OCaml Fallback**: The file is re-read using a pure OCaml parser. Note that this fallback is more memory-intensive and may encounter `Out_of_memory` errors for files larger than a few gigabytes on systems with limited RAM.

## Recommendations for Large Data

For datasets exceeding 2-3 GB:
1. **Prefer Parquet**: Convert your CSVs to Parquet using R (`arrow::write_parquet`) or Python (`pandas.to_parquet`) before reading them into T.
2. **Use Standard CSVs**: If you must use CSV, ensure it uses the default comma separator and has no leading comment lines to stay on the high-performance native path.
3. **Memory Limits**: The pure OCaml fallback path is limited by OCaml's heap and string size limits (on 64-bit systems this is large, but still less efficient than Arrow's memory mapping).


# FILE: docs/literate-programming-quarto.md

# Literate Programming with Quarto

## Quick Setup with Quarto

T provides a specialized Quarto filter (`tlang`) that allows you to execute T code chunks directly in your `.qmd` documents. 

### Installing the T Plugin

The T plugin is managed automatically within a T project. You don't need to download it manually; T's dependency management handles it.

1.  **Add Quarto to your project**: In your `tproject.toml`, ensure `quarto` is in the `additional-tools`:
    ```toml
    [additional-tools]
    packages = ["quarto"]
    ```
2.  **Provision the extension**: Run `t update` in your terminal.
3.  **Enter the environment**: Run `nix develop`.
    
Upon entering the environment, T will symlink the `tlang` extension from the Nix store into your project's `_extensions/` directory.

### Enabling the Filter

Add the `tlang` filter to your document's YAML front matter:

```yaml
---
title: "My T Analysis"
format: html
filters:
  - tlang
---
```

## Writing Quarto Blocks

You can now use `{t}` code chunks in your document. These chunks are executed by the T interpreter during rendering.

````markdown
```{t}
#| label: load-data
df = read_csv("mtcars.csv")
df |> glimpse
```
````

### Block Options

- `eval`: Set to `false` to show the code without executing (default: `true`).
- `echo`: Set to `false` to hide the code and only show the output (default: `true`).
- `results`: Set to `hide` to suppress any printed output.
- `fig-cap`: Add a caption if the chunk generates a plot (via an R/Python sub-node).

---


## Defining a Quarto Node

A Quarto node in a pipeline takes a `.qmd` file as input and renders it to a target format (default is HTML).

```t
p = pipeline {
  data = node(command = read_csv("data.csv") |> filter($age > 18))
  
  report = node(
    script = "analysis.qmd",
    runtime = Quarto
  )
}
```

### Implicit Dependencies

When a `.qmd` file uses `read_node("name")`, T automatically detects this and adds a dependency from the Quarto node to the specified node (`data` in the example above).

## Using Data from T in Quarto

Within your `.qmd` file, you can access data generated by other nodes in the same pipeline using the `read_node()` function.

### In R Chunks

````qmd
---
title: "Pipeline Analysis"
format: html
---

# Analysis

```{r}
# read_node is substituted by T during the build
df <- read_node("data")
summary(df)
```
````

### How it Works

When the pipeline is built via Nix:
1. T detects `read_node("node_name")` calls in the `.qmd` source.
2. It generates a Nix derivation where the absolute path to the node's artifact (in the Nix store) is provided via environment variables.
3. During the Nix build, a `sed` substitution replaces `read_node("node_name")` with the actual path to the artifact.
4. Quarto renders the document using these absolute paths.

## Exporting Results

Because T pipelines are built in the Nix store (which is read-only), rendered reports remain in `/nix/store/...`. To inspect or publish them, use the `pipeline_copy()` function to bring them into your local workspace.

```t
-- Build the pipeline
populate_pipeline(p, build = true)

-- Copy all artifacts to ./pipeline-output/
pipeline_copy()
```

The rendered HTML and its accompanying files will be available in `pipeline-output/report/artifact/`.

## Configuring Dependencies

If your Quarto document uses R or Python chunks, you must ensure the necessary packages are available in the project's `tproject.toml`.

```toml
[r-dependencies]
packages = ["jsonlite", "ggplot2"]

[additional-tools]
packages = ["quarto", "which"]
```

> [!NOTE]
> Always include `quarto` and `which` in `additional-tools` if you are using Quarto nodes.

## Multi-Language Reporting

Quarto allows you to blend multiple languages in a single document. Since T orchestrates the data flow, you can:
1. Process raw data in **T**.
2. Perform complex statistical modeling in **R**.
3. Render a comprehensive reporting doc in **Quarto** that consumes both the processed data and the model parameters.


# FILE: docs/plotting.md

# Plotting and Visual Inspection

T is primarily an orchestration engine and does not currently provide its own native low-level plotting library. Instead, T's `show_plot()` function supports a wide range of visualization libraries across R and Python:

- **R**: `ggplot2`
- **Python**: `matplotlib`, `seaborn`, `plotly`, `altair`, `plotnine`

One of T's unique features is **Automated Visual Metadata Capture**. When you generate a plot in an R or Python node, T "sees" the plot object and automatically extracts its structural metadata during the build process.

---

## Plotting in Polyglot Pipelines

Generating a plot in T is as simple as returning a plot object from a foreign-language node.

### Example: ggplot2 in R

```t
p = pipeline {
    p_ggplot = rn(
        command = <{
            library(ggplot2)
            ggplot(mtcars, aes(x = wt, y = mpg)) +
                geom_point() +
                labs(title = "Fuel Economy")
        }>
    )
}
```

### Example: matplotlib in Python

```t
    p = pipeline {
      p_matplotlib = pyn(
        command = <{
            import matplotlib.pyplot as plt
            fig, ax = plt.subplots()
            ax.scatter([2.6, 3.2, 3.4], [21.0, 19.2, 18.1])
            ax.set_title("Fuel Economy")
            fig
        }>
      )
    }
```

In both cases, T recognizes that the node result is a visualization.

---

## Visual Metadata Capture

When you build a pipeline containing these nodes, T creates two artifacts for each plotting node in the Nix store:
1.  **The Artifact**: The serialized plot object (e.g., an RDS file for `ggplot2`).
2.  **The Metadata (`viz`)**: A JSON representation of the plot's contents.

T automatically extracts:
- **Title**: The main title of the plot.
- **Backend**: The runtime used to produce the plot (`"R"` or `"Python"`).
- **Class**: The plot library or object type (e.g., `"ggplot"`, `"matplotlib"`, `"seaborn"`, `"plotly"`, `"altair"`).
- **Labels**: Axis labels and legends.
- **Layers**: The types of geometries present (e.g., "point", "line").
- **Mappings**: In `ggplot2`, the aesthetic mappings (x, y, color, etc.).

---

## Inspecting Plots with `read_node()`

Because T captures this metadata, you can inspect the "contents" of a plot directly from your T scripts or the REPL without needing to render it to an image.

When you call `read_node()` on a plotting node, T returns the **metadata dictionary** instead of the binary artifact.

```t
> g = read_node("p_ggplot")
> print(g.title)
"Fuel Economy"

> print(g.layers)
["point"]

> print(g.labels)
{ x: "wt", y: "mpg", title: "Fuel Economy" }
```

This "Transparent Plotting" enables programmatic verification of visualizations—for example, a test script could assert that a generated plot has the correct title and includes a regression line layer.

---

## REPL Display

Plot metadata is pretty-printed in the REPL instead of dumping raw runtime-specific structures.

For example, a `ggplot` node read through `read_node()` displays as a structured object with fields such as:

- `class`
- `backend`
- `title`
- `mapping`
- `labels`
- `layers`

This makes plotting nodes inspectable even when the underlying artifact is binary (`.rds` or Python pickle).

---

## Plotting in Literate Programming

When using [Quarto](literate-programming-quarto.html) with T pipelines, it is important to understand how `read_node()` behaves depending on the language of the code chunk.

### In T Chunks
Within a `{t}` code block, `read_node()` follows the same behavior as the REPL: it returns the **JSON metadata dictionary**. 

<pre><code class="language-markdown">```{t}
#| echo: false
g = read_node("p_ggplot")
print(g.title)
```</code></pre>
*Output: "Fuel Economy"*

This is useful for including summary information about your visualizations directly in the text of your report.

### In R and Python Chunks
To actually **render** the plot in your report, you must use an `{r}` or `{python}` chunk. However, in these environments, `read_node()` is a preprocessor token that T replaces with the **absolute path string** to the artifact in the Nix store. 

Because `read_node()` returns a path, you must manually load the artifact using the specialized reader for that language.

#### Example: Rendering a ggplot2 node in R
<pre><code class="language-markdown">```{r}
#| echo: false
# read_node("p_ggplot") becomes '/nix/store/.../artifact'
p <- readRDS(read_node("p_ggplot"))
p
```</code></pre>

#### Example: Rendering a matplotlib node in Python
<pre><code class="language-markdown">```{python}
#| echo: false
try:
    import cloudpickle as pickle
except ImportError:
    import pickle
# read_node("p_matplotlib") becomes '/nix/store/.../artifact'
with open(read_node("p_matplotlib"), "rb") as f:
    fig = pickle.load(f)
fig
```</code></pre>

This dual behavior ensures that you can use T for programmatic inspection and R/Python for high-fidelity visual rendering, all while maintaining strict Nix-based reproducibility.

---

## Opening Plots with `show_plot()`

`show_plot()` renders a plotting artifact in a fresh Nix sandbox, writes the rendered image to `_pipeline/`, and then opens the image locally.

It accepts:

- an unbuilt `rn()` / `pyn()` node
- a built `ComputedNode`
- a `read_node()` result that still points back to a built plot node

The rendered output is currently written as a PNG file under `_pipeline/`.

Add an opener in `tproject.toml` if you want to override the default viewer:

```toml
[visualization-tool]
command = "xdg-open"
```

The value must be a single executable name or an absolute path to an executable. When no custom tool is configured, T falls back to:

1. `open` on systems where it is available
2. `xdg-open` otherwise

```t
p = rn(command = <{
  library(ggplot2)
  ggplot(mtcars, aes(wt, mpg)) + geom_point()
}>)

show_plot(p)
```

`show_plot(p)` returns the local path of the rendered PNG after launching the viewer.

### Runtime Requirements

`show_plot()` renders the plot by reloading the stored artifact inside a Nix sandbox:

- **R / ggplot2** nodes require `ggplot2` to be present in `[r-dependencies].packages`.
- **Python / matplotlib** nodes require `matplotlib` and `cloudpickle` in `[py-dependencies].packages`.
- **Python / seaborn** nodes require `seaborn`, `matplotlib`, and `cloudpickle` in `[py-dependencies].packages`.
- **Python / Plotly** requires `plotly`, `kaleido` (for static image export), and `cloudpickle` in `[py-dependencies].packages`.
- **Python / Altair** requires `altair`, `vl-convert-python` (preferred), and `cloudpickle` in `[py-dependencies].packages`.
- **Python / Plotnine** requires `plotnine`, `pandas`, and `cloudpickle` in `[py-dependencies].packages`.

### Automated Dependency Detection

When you use these libraries in a `pyn()` node, T's static analyzer will automatically detect the imports and prompt you to add the required rendering dependencies to your `tproject.toml` if they are missing.

| Detected Import | Automatically Suggested Packages |
| :--- | :--- |
| `import matplotlib` | `matplotlib`, `cloudpickle` |
| `import seaborn` | `seaborn`, `matplotlib`, `cloudpickle` |
| `import plotnine` | `plotnine`, `pandas`, `cloudpickle` |
| `import plotly` | `plotly`, `kaleido`, `cloudpickle` |
| `import altair` | `altair`, `vl-convert-python`, `cloudpickle` |

Example project configuration:

```toml
[r-dependencies]
packages = ["ggplot2"]

[py-dependencies]
version = "python314"
packages = ["matplotlib", "plotnine", "seaborn", "plotly", "kaleido"]

[visualization-tool]
command = "xdg-open"
```

### Files Written to `_pipeline/`

When you call `show_plot()`, T creates local helper files in `_pipeline/`, including:

- a temporary Nix expression used for rendering
- the rendered PNG image that is opened locally

This keeps the visualization workflow aligned with T's existing pipeline artifact conventions.

See the [T Pipeline Demos](demos.html) for real-world examples of pipelines generating interactive and static reports.


# FILE: docs/factors.md

# Factors and `fct_*` Helpers in T

This guide explains how factors work in T, when to use `factor()` versus `fct()`, and how the `fct_*` family helps you reorder, relabel, and combine categorical data.

---

## The Basic Idea

A factor is categorical data with an explicit list of levels.

That level list matters because operations such as `arrange()` use the level order instead of alphabetical order.

```t
sizes = factor(["medium", "small", "large"], levels = ["small", "medium", "large"])
levels(sizes)
-- ["small", "medium", "large"]
```

This makes factors useful for ordered categories such as:

- shirt sizes,
- survey responses,
- month names,
- reporting buckets.

---

## Creating Factors

### `factor()` — explicit categorical levels

Use `factor()` when you want to control the level order yourself.

```t
priority = factor(
  ["medium", "low", "high", "medium"],
  levels = ["low", "medium", "high"]
)
```

If you do not provide `levels`, `factor()` derives them from the data.

### `fct()` — levels follow first appearance

Use `fct()` when you want levels to keep the order in which values first appear.

```t
status = fct(["new", "in_progress", "done", "new"])
levels(status)
-- ["new", "in_progress", "done"]
```

### `as_factor()` — coerce existing values

`as_factor()` is the convenient coercion form for turning an existing vector or column into factor data.

```t
df |> mutate($segment = as_factor($segment))
```

### `ordered()` — ordered factors

Use `ordered()` when the order is meaningful and should be preserved as an ordered factor.

```t
ratings = ordered(
  ["bad", "ok", "great"],
  levels = ["bad", "ok", "great"]
)
```

---

## Why the `fct_*` Prefix Exists

The `fct_*` prefix is used for helpers that manipulate factor levels after creation.

These helpers are analogous to the factor tools popularized by `forcats` in R:

- they keep the input as factor data,
- they operate on levels or factor ordering,
- and they make factor-specific intent obvious in a pipeline.

Examples:

```t
fct_infreq(x)
fct_rev(x)
fct_recode(x, LARGE = "large")
fct_reorder(x, scores)
fct_lump_n(x, n = 3)
```

---

## Core Factor Workflow

### Inspect levels

```t
levels(priority)
```

### Reorder levels by frequency

```t
df |> mutate($segment = fct_infreq($segment))
```

### Reverse the current order

```t
df |> mutate($segment = fct_rev($segment))
```

### Recode level names

```t
df |> mutate($segment = fct_recode($segment, ENTERPRISE = "enterprise", SMB = "small_business"))
```

### Reorder levels using another variable

```t
df |> mutate($segment = fct_reorder($segment, $revenue))
```

### Move selected levels to the front or after a position

```t
df |> mutate($segment = fct_relevel($segment, "enterprise", "midmarket"))
```

### Collapse several levels into broader groups

```t
df |> mutate($segment = fct_collapse($segment, commercial = ["enterprise", "midmarket"], self_serve = "small_business"))
```

---

## Lumping and "Other"

The `fct_lump_*` helpers keep the most important levels and group the rest into an `Other` bucket by default.

### Keep the top `n` levels

```t
fct_lump_n($species, n = 2)
```

### Keep levels with at least a minimum count

```t
fct_lump_min(fct(["a", "a", "b", "c"]), 2)
levels(fct_lump_min(fct(["a", "a", "b", "c"]), 2))
-- ["a", "Other"]
```

### Keep levels above a minimum proportion

```t
fct_lump_prop($segment, 0.10)
```

You can also set a custom replacement label with `other_level = "Misc"`.

---

## Other Useful Helpers

### Keep or drop selected levels with `fct_other()`

```t
levels(fct_other(fct(["a", "b", "c"]), keep = ["a"]))
-- ["a", "Other"]
```

### Remove unused levels with `fct_drop()`

```t
levels(fct_drop(factor(["a", "b"], levels = ["a", "b", "c"])))
-- ["a", "b"]
```

### Add levels without changing existing values with `fct_expand()`

```t
levels(fct_expand(fct(["a"]), "b", "c"))
-- ["a", "b", "c"]
```

### Combine factors with unified levels using `fct_c()`

```t
levels(fct_c(fct(["a"], levels = ["a", "b"]), fct(["c"])))
-- ["a", "b", "c"]
```

---

## Sorting with Factors

A factor keeps its declared level order during sorting.

```t
df = crossing(size = ["medium", "small", "large"], id = [1, 2])

df
  |> mutate($size_fct = factor($size, levels = ["small", "medium", "large"]))
  |> arrange($size_fct)
```

This sorts rows by `small`, then `medium`, then `large`, even though alphabetical order would be different.

---

## Choosing the Right Helper

Use:

- `factor()` when you want explicit levels,
- `fct()` when you want first-appearance order,
- `as_factor()` when coercing an existing column,
- `ordered()` when the factor should be marked as ordered,
- `fct_*` helpers when changing levels after creation,
- `levels()` when you need to inspect the current level set.

---

These factor helpers are currently implemented alongside the data-manipulation verbs in T's `colcraft` package, but the naming convention is the same idea you would expect from a dedicated factor-toolkit family: factor creation helpers plus `fct_*` level-manipulation helpers.

---

## Next Steps

Now that you can handle categorical data, explore vector operations and statistical modeling in T:

1. **[Arrays and Matrices](arrays.md)** — Vector and matrix operations.
2. **[Formulas and Models](formulas.md)** — Statistical modeling in T.
3. **[Pipeline Tutorial](pipeline_tutorial.md)** — Build reproducible data pipelines.
4. **[API Reference](api-reference.md)** — Complete function reference by package.


# FILE: docs/string_manipulation.md

# String Manipulation in T

This guide explains how string manipulation functions are named in T, when the `str_` prefix is used, and which related helpers intentionally keep their original names.

---

## The Basic Rule

String transformation and formatting functions in T use the `str_` prefix.

This makes it easier to distinguish them from:

- generic helpers in other packages,
- functions that have non-string behavior,
- selection helpers used in data manipulation.

Examples:

```t
str_nchar("hello")          -- 5
str_substring("hello", 1, 4) -- "ell"
str_replace("banana", "a", "o") -- "bonono"
str_trim("  hello  ")       -- "hello"
str_join(["a", "b", "c"], "-") -- "a-b-c"
str_string(42)               -- "42"
str_split("a,b,c", ",")    -- ["a", "b", "c"]
```

---

## Functions That Use `str_`

The shorter string-focused helpers follow this naming convention:

- `str_nchar()`
- `str_substring()`
- `str_replace()`
- `str_trim()`
- `str_lines()`
- `str_words()`
- `str_sprintf()`
- `str_join()`
- `str_string()`
- `str_split()`

The `strsplit()` name was normalized to `str_split()` to match the rest of the string API.

---

## Why Some Names Stay Unchanged

Not every string-related helper is renamed.

Some functions deliberately keep their original names because they are already descriptive, are shared with another subsystem, or would become awkward if prefixed.

Examples that remain unchanged include:

- `contains()`
- `starts_with()`
- `ends_with()`
- `replace_first()`
- `trim_start()`
- `trim_end()`
- `char_at()`
- `index_of()`
- `last_index_of()`
- `to_lower()`
- `to_upper()`
- `is_empty()`
- `slice()`

In particular, `contains()`, `starts_with()`, and `ends_with()` are also used as column-selection helpers in `colcraft`, so keeping those names makes the data-manipulation API more consistent.

---

## Common Patterns

### Inspecting strings

```t
str_nchar("hello")
is_empty("")
contains("tlang", "lang")
starts_with("prefix", "pre")
ends_with("suffix", "fix")
```

### Extracting and modifying text

```t
str_substring("abcdef", 1, 4)
char_at("abcdef", 2)
str_replace("banana", "a", "o")
replace_first("banana", "a", "o")
```

### Cleaning and splitting text

```t
str_trim("  hello  ")
trim_start("  hello  ")
trim_end("  hello  ")
str_lines("a\nb\nc")
str_words("hello   world")
str_split("a,b,c", ",")
```

### Formatting and conversion

```t
str_sprintf("Hello, %s!", "world")
str_join(["red", "green", "blue"], ", ")
str_string(3.14)
```

---

## Selection Helpers vs String Helpers

When working with DataFrames, some names such as `starts_with()` and `contains()` can be used for column selection:

```t
df |> select(starts_with("petal"))
df |> select(contains("width"))
```

When called with string arguments, the same names still behave as string predicates:

```t
starts_with("petal_width", "petal")
contains("petal_width", "width")
```

That is why these names are intentionally left without the `str_` prefix.

---

## Related Reference Pages

For per-function details, see the reference pages:

- [`str_nchar`](reference/nchar.html)
- [`str_substring`](reference/substring.html)
- [`str_replace`](reference/replace.html)
- [`str_sprintf`](reference/sprintf.html)
- [`str_join`](reference/join.html)
- [`str_string`](reference/string.html)
- [`str_split`](reference/strsplit.html)
- [`contains`](reference/contains.html)
- [`starts_with`](reference/starts_with.html)
- [`ends_with`](reference/ends_with.html)

---

## Next Steps

Now that you can manipulate text, explore categorical data and vector operations in T:

1. **[Factors & Categorical Data](factors.md)** — Learn how to work with categorical data.
2. **[Arrays and Matrices](arrays.md)** — Vector and matrix operations.
3. **[Formulas and Models](formulas.md)** — Statistical modeling in T.
4. **[API Reference](api-reference.md)** — Complete function reference by package.


# FILE: docs/handling_dates.md

# Handling Dates and Times in T

The `chrono` package provides comprehensive tools for working with dates and times, heavily inspired by R's `lubridate`. 

## Core Types

T supports several temporal types:
- **Date**: A calendar date (e.g., `2024-03-08`).
- **Datetime**: A precise point in time with a timezone label.
- **Interval**: A span of time between two specific instants.
- **Period**: A human-friendly duration (e.g., "2 months and 3 days").
- **Duration**: A precise physical duration in seconds.

## Parsing Dates

You can parse strings into dates using shorthand helpers:

```t
d1 = ymd("2024-01-15")
d2 = mdy("01-15-2024")
d3 = dmy("15-01-2024")

dt1 = ymd_hms("2024-01-15 09:30:00")
dt2 = ymd_hm("2024-01-15 09:30")
```

For custom formats, use `parse_date` or `parse_datetime`:

```t
d = parse_date("15 Jan 2024", "%d %b %Y")
```

## Creating Dates from Components

If you have numeric components, use `make_date` or `make_datetime`:

```t
d = make_date(year = 2024, month = 3, day = 8)
dt = make_datetime(year = 2024, month = 3, day = 8, hour = 12, min = 0, sec = 0, tz = "Europe/Paris")
```

## Component Extraction

Extract specific parts of a date or datetime:

```t
year(d)       -- 2024
month(d)      -- 3
month(d, label = true) -- "Mar"
day(d)        -- 8
wday(d)       -- Week day (1-7)
hour(dt)      -- 12
am(dt)        -- true
pm(dt)        -- false
```

## Date Arithmetic

T supports intuitive date arithmetic using periods:

```t
-- Add 3 months to a date
next_app = ymd("2024-01-31") + months(3) -- 2024-04-30

-- Subtract 1 week
last_week = today() - weeks(1)
```

Arithmetic is "calendar-aware". Adding a month to January 31st results in the last day of February.

## Rounding

Round dates to the nearest calendar unit:

```t
floor_date(dt, "hour")    -- Round down to start of hour
ceiling_date(d, "month")  -- Round up to start of next month
round_date(dt, "day")     -- Round to nearest day
```

## Intervals and %within%

Intervals represent a fixed span of time. You can check if a date falls within an interval using the `%within%` operator:

```t
vacation = interval(ymd("2024-07-01"), ymd("2024-07-15"))
ymd("2024-07-04") %within% vacation -- true
```

## Timezones

Timezones in T are currently handled as labels. 

- `with_tz(dt, tz)`: Changes the timezone label without altering the underlying time.
- `force_tz(dt, tz)`: Similar to `with_tz`, used to clarify or correct a timezone label.

## Example Workflow

```t
df = read_csv("sales.t") |>
  mutate(
    date = ymd($order_date),
    month = month($date, label = true),
    quarter = quarter($date)
  ) |>
  filter(year($date) == 2024) |>
  group_by($month) |>
  summarize($total = sum($sales))
```

---

## Next Steps

Now that you can handle temporal data, explore text processing and categorical data in T:

1. **[String Manipulation](string_manipulation.md)** — Explore powerful functions for text processing and regular expressions.
2. **[Factors & Categorical Data](factors.md)** — Learn how to work with categorical data.
3. **[Arrays and Matrices](arrays.md)** — Vector and matrix operations.
4. **[API Reference](api-reference.md)** — Complete function reference by package.


# FILE: docs/arrays.md

# Numerical Arrays (NDArrays)

Numerical arrays (NDArrays) are first-class data structures in T designed for high-performance numerical computation, linear algebra, and statistical operations. Unlike lists, NDArrays have a fixed shape and optimized storage for numeric data.

## Creating Arrays

You can create an NDArray using the `ndarray()` function. It can infer the shape from a nested list or accept an explicit shape.

### From Nested Lists
```t
-- Create a 1D array (vector)
v = ndarray([1, 2, 3, 4, 5])

-- Create a 2D array (matrix)
m = ndarray([[1, 2, 3], [4, 5, 6]])

-- Access shape and data
print(shape(m))        -- [2, 3]
print(ndarray_data(m)) -- [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
```

### With Explicit Shape
```t
-- Create a 2x3 matrix from a flat list
m = ndarray([1, 2, 3, 4, 5, 6], shape = [2, 3])
```

## Array Operations

### Element-wise Arithmetic
NDArrays support standard arithmetic operators (+, -, *, /) and comparison operators (==, !=, <, >, <=, >=). These operations are applied element-wise.

```t
a = ndarray([[1, 2], [3, 4]])
b = ndarray([[5, 6], [7, 8]])

c = a + b    -- [[6, 8], [10, 12]]
d = a * 2    -- [[2, 4], [6, 8]] (Broadcasting)
```

### Broadcasting
Operations between an NDArray and a scalar value automatically "broadcast" the scalar to match the shape of the array.

```t
m = ndarray([1, 2, 3])
res = m + 10  -- [11, 12, 13]
```

### Linear Algebra
T provides specific functions for matrix operations:

- **`matmul(a, b)`**: Performs matrix multiplication between two 2D arrays.
- **`kron(a, b)`**: Computes the Kronecker product of two 2D arrays.
- **`diag(x)`**: For a 1D array, returns a square diagonal matrix; for a 2D array, extracts its main diagonal.
- **`inv(a)`**: Computes the inverse of a square 2D array.

```t
a = ndarray([[1, 2], [3, 4]])
i = ndarray([[1, 0], [0, 1]])

res = matmul(a, i) -- Returns 'a'
main_diag = diag(a)  -- [1.0, 4.0]
inverse = inv(a)     -- [[-2.0, 1.0], [1.5, -0.5]]
```

## Reshaping and Introspection

- **`shape(arr)`**: Returns the dimensions of the array as a list.
- **`ndarray_data(arr)`**: Returns the underlying flat data as a list of floats.
- **`reshape(arr, new_shape)`**: Returns a new array with the same data but a different shape. The total number of elements must remain consistent.

```t
m = ndarray([1, 2, 3, 4, 5, 6], shape = [2, 3])
m2 = m |> reshape([3, 2]) -- Reshapes to 3 rows, 2 columns
```

## Best Practices
- NDArrays cannot contain `NA` values. Handle missing data before converting to arrays.
- Prefer NDArrays over lists for large numerical datasets to benefit from optimized performance and specialized linear algebra functions.

---

## Next Steps

Now that you can work with numerical arrays, explore statistical modeling and reproducible pipelines in T:

1. **[Formulas and Models](formulas.md)** — Statistical modeling in T.
2. **[Pipeline Tutorial](pipeline_tutorial.md)** — Build reproducible data pipelines.
3. **[API Reference](api-reference.md)** — Complete function reference by package.


# FILE: docs/formulas.md

# Formulas in T

Formulas provide a declarative way to specify statistical models, inspired by R.

## Syntax

```t
response ~ predictor
```

The `~` operator creates a Formula object that can be passed to modeling functions.

## Examples

```t
-- Simple linear regression
model = lm(data = df, formula = y ~ x)

-- Multiple regression
model = lm(data = df, formula = y ~ x1 + x2 + x3)

-- Interaction terms
model = lm(data = df, formula = y ~ x1 * x2)
```

## Supported Functions

- `lm()` - Linear regression

## `lm()` - Linear Regression

Fit a linear model using least squares.

### Signature

```t
lm(data: DataFrame, formula: Formula, ...) -> Dict
```

### Arguments

- `data`: DataFrame containing the variables
- `formula`: Formula specifying the model (e.g., `y ~ x`)

### Returns

Dictionary containing:
- `formula`: The model formula
- `intercept`: Estimated intercept
- `slope`: Estimated slope (coefficient)
- `r_squared`: R² statistic
- `residuals`: Vector of residuals
- `n`: Number of observations
- `response`: Name of response variable
- `predictor`: Name of predictor variable

### Examples

```t
data = read_csv("mtcars.csv")
model = lm(data = data, formula = mpg ~ hp)
print(model.r_squared)
```

## Current Limitations

- Intercept control: `y ~ x + 1` vs `y ~ x - 1`
- Transformations: `y ~ log(x)`

---

## Next Steps

Now that you've explored formulas, learn about statistical modeling and pipelines in T:

1. **[Models and Prediction](models.md)** — Comprehensive guide to statistical models.
2. **[Pipeline Tutorial](pipeline_tutorial.md)** — Build reproducible data pipelines.
3. **[API Reference](api-reference.md)** — Complete function reference by package.


# FILE: docs/lens.md

# Composable Lenses: Reaching the Unreachable

> How to navigate and transform nested data structures that were previously painful or impossible to reach.

Traditional data manipulation verbs like `mutate()`, `filter()`, and `arrange()` are designed for flat DataFrames. Once your data becomes multi-dimensional—whether through nesting DataFrames (`nest()`) or building complex Pipelines—standard verbs often lead to a "pyramid of doom."

Lenses solve this by providing a first-class, composable way to "zoom in" on nested values and transform them surgically.

---

## Part I: Why Lenses

### 1. The Core Problem: Deeply Nested Structures

Consider a dataset that is genuinely hierarchical: a `clients` DataFrame where each row's `projects` column holds another DataFrame of that client's projects, and each project's `milestones` column holds a further DataFrame of milestones. Each client has a different number of projects; each project has a different number of milestones. This kind of structure arises naturally after a `nest()` call, or when loading hierarchical data from a JSON API.

```t
-- clients: DataFrame
--   $name     : String
--   $projects : DataFrame (nested)
--       $title      : String
--       $milestones : DataFrame (nested)
--           $label   : String
--           $pct_int : Int    -- completion percentage, 0–100
```

A business requirement: **apply a 10-point uplift to every milestone's `$pct_int` value** (an end-of-quarter adjustment). Because the number of milestones varies per project and per client, you cannot simply `mutate($pct_int = $pct_int + 10)` on the top-level DataFrame—`$pct_int` lives three levels down.

#### The Nested Mutate Approach (The "Pyramid of Doom")

With standard verbs you have to peel back every layer manually, inventing a new lambda variable at each level:

```t
updated_clients = clients |> mutate(
  $projects = map($projects, \(proj)
    proj |> mutate(
      $milestones = map($milestones, \(ms)
        ms |> mutate($pct_int = min($pct_int + 10, 100))
      )
    )
  )
)
```

This is fragile: rename a column or add another level of nesting and you rewrite the entire block. The deeper the hierarchy, the worse it gets.

#### The Lens Approach (Declarative Pathing)

Lenses let you declare the **path** to the target once, then apply it in a single operation. T handles traversal and immutable reconstruction automatically.

```t
-- Define the path once; compose() is variadic
pct_l = compose(col_lens("projects"), col_lens("milestones"), col_lens("pct_int"))

-- Apply the transformation everywhere in one line
updated_clients = clients |> over(pct_l, \(x) min(x .+ 10, 100))
```

**Why lenses win:**

1. **Readability**: The path is declared once; the operation is a single flat expression.
2. **Vectorization**: `over()` distributes your function across all matching values at every level automatically. When the focused value is a Vector (as it is here), broadcasting operators like `.+` and `.*` are required for element-wise operations; scalar operators will not work as intended.
3. **Reuse**: Name a lens once and use it with `get()`, `set()`, or `over()` anywhere in the codebase.

---

### 2. The Problem: Surgical Edits to Pipelines

Pipelines in T are often treated as immutable specifications. If you needed to change an environment variable for a deep node or update a cached result before building, you previously had to reconstruct the pipeline or use internal hacks.

#### The Solution: Orchestration Lenses

Specialized lenses allow you to treat a Pipeline as a queryable data structure.

- **`node_lens(node_name)`**: Targets the cached result value of a specific node.
- **`env_var_lens(node_name, var_name)`**: Targets a specific environment variable for a given node.

```t
p = build_pipeline("complex_analysis.t")

-- Inject a debug flag into a specific node's environment
debug_l = env_var_lens("compute_stats", "DEBUG")
p_debug = p |> set(debug_l, "true")

-- Re-run with the updated environment
build_pipeline(p_debug)
```

---

## Part II: Lens API

### 3. Core Operations

| Function | Signature | Description |
| :--- | :--- | :--- |
| **`set(data, lens, value)`** | `(A, Lens, B) -> A` | Replaces the focused value. |
| **`over(data, lens, f)`** | `(A, Lens, B -> B) -> A` | Applies a function to the focused value. |
| **`modify(data, lens1, f1, ...)`** | `(A, Lens, B -> B, ...) -> A` | Applies multiple lens+function pairs in sequence. |
| **`compose(...)`** | `(...Lens) -> Lens` | Chains lenses into a single path (left-to-right). |

> **Broadcasting**: When `over()` focuses on a column, the function receives a **Vector**. Use broadcasting operators (`.+`, `.*`, etc.) for element-wise math, not scalar operators. This applies at every level of a nested traversal.

#### `modify()`: Multiple transformations in one call

When you need to transform several paths in one operation, `modify()` keeps the update list flat and readable instead of chaining multiple `over()` calls.

```t
-- Two distinct paths through the same nested structure
pct_l   = compose(col_lens("projects"), col_lens("milestones"), col_lens("pct_int"))
label_l = compose(col_lens("projects"), col_lens("milestones"), col_lens("label"))

updated_clients = clients |> modify(
    pct_l,   \(x) min(x .+ 10, 100),
    label_l, \(s) s + " ✓"
)
```

---

### 4. Primitive Lenses

#### `col_lens(name)`

Targets a column in a DataFrame, a key in a Dictionary, or a named field in a nested record. This is the primary building block for navigating hierarchical structures.

```t
employees = dataframe([[name: "Alice", salary: 50000],
                       [name: "Bob",   salary: 48000]])

salary_l = col_lens("salary")

-- Replace values
raised   = employees |> set(salary_l, [60000, 58000])

-- Transform values
after_tax = raised |> over(salary_l, \(x) x .* 0.75)
```

#### `idx_lens(index)`

Focuses on a single 0-based index in a **List** or **Vector**.

```t
scores = [10, 20, 30]

-- Correct the second score
scores2 = scores |> set(idx_lens(1), 99)  -- [10, 99, 30]

-- Update a nested list
data = [ids: [101, 102, 103]]
target_id_l = compose(col_lens("ids"), idx_lens(2))
data2 = data |> set(target_id_l, 999)    -- [ids: [101, 102, 999]]
```

#### `row_lens(index)`

Focuses on a specific row in a **DataFrame**. Compose with `col_lens` for cell-level access.

```t
df  = dataframe([[x: 1, y: 10], [x: 2, y: 20]])

-- Update a single cell (row 0, column "y")
cell_l = compose(row_lens(0), col_lens("y"))
df2 = df |> set(cell_l, 99)

-- Transform a single cell
df3 = df |> over(cell_l, \(v) v * 10)
```

### 4.1 Cross-Node Retrieval in Sandboxes

A unique feature of `node_lens` is its ability to perform **cross-node artifact retrieval** when used within a Nix-managed pipeline node.

While standard lenses like `col_lens` require a data source (e.g., `get(df, l)`), a `node_lens` used with a single-argument `get()` will automatically locate and deserialize the artifact of a sibling node from the sandbox environment.

```t
-- Inside a node script (e.g., node_b)
-- Assuming node_a is a dependency of this node:

target_data = get(node_lens("node_a"))
```

This works because T automatically propagates artifact paths of dependencies via environment variables (`T_NODE_<name>`) within the Nix sandbox. T handles the path resolution, integrity checks, and deserialization (using the appropriate artifact class) automatically.

---

### 5. Traversals: `filter_lens`

> **Note:** `filter_lens` is a **traversal**, not a lens—it focuses on *multiple* elements simultaneously rather than a single one. Unlike a lens, which always focuses on exactly one location, a traversal may focus on zero, one, or many locations. 

`filter_lens(predicate)` focuses on every element or row satisfying a condition. It works on **Lists**, **Vectors**, and **DataFrames**.

```t
scores = [1, 2, 3, 4, 5]

-- Add 10 to every even number
even_l = filter_lens(\(x) x % 2 == 0)
scores2 = scores |> over(even_l, \(x) x + 10)
-- [1, 12, 3, 14, 5]
```

#### Deep Conditional Updates
Lenses really shine when you need to update a deep field based on a property of an intermediate container.

```t
-- For every city in Switzerland, increase population by 0.5m
swiss_l = compose(
  col_lens("countries"), 
  filter_lens(\(c) c.name == "Switzerland"), 
  col_lens("cities"), 
  col_lens("pop")
)

world2 = world |> over(swiss_l, \(p) p .+ 0.5)
```

---

## Part III: Data Science Patterns

### 6. Navigating Nested Model Results
As a data scientist, you often deal with nested lists from model summaries or API responses. While `colcraft` handles flat DataFrames, Lenses are the tool for everything else.

Consider a nested result from a cross-validation run:
```t
cv_results = [
  fold1: [metrics: [rmse: 0.1, mae: 0.05], status: "ok"],
  fold2: [metrics: [rmse: 0.12, mae: 0.06], status: "ok"],
  fold3: [metrics: [rmse: NA, mae: NA], status: "failed"]
]
```

**Task: Extract all RMSE values for successful folds.**
```t
-- Combine filtering and pathing
rmse_path = compose(
  filter_lens(\(f) f.status == "ok"),
  col_lens("metrics"),
  col_lens("rmse")
)

successful_rmses = get(cv_results, rmse_path)
-- [0.1, 0.12]
```

### 7. Mass-Updating Configuration Dicts
Lenses allow you to surgically update hyperparameters nested deep within a configuration structure without rebuilding the entire Dict.

```t
config = [
  model: [
    params: [learning_rate: 0.01, layers: [64, 32]],
    type: "mlp"
  ],
  data: [path: "data.csv"]
]

-- Update learning rate deep in the config
lr_l = compose(col_lens("model"), col_lens("params"), col_lens("learning_rate"))
new_config = config |> set(lr_l, 0.005)
```

---

## Part IV: Advanced Patterns

### 6. Orchestration: Dynamic Pipeline Queries

Because lenses are first-class values, you can build them dynamically to query or modify pipelines based on configuration data.

```t
p = pipeline {
    model_r = node(command = <{ train_model(df) }>, runtime = R)
    model_py = node(command = <{ train_model(df) }>, runtime = Python)
}

-- Choose which model to query at runtime
best_model_name = "model_py"
model_value = get(p, node_lens(best_model_name))
```

### 7. Core Orchestration: `node_meta_lens`

While `node_lens` focuses on a node's *result*, `node_meta_lens` focuses on its *inner configuration*. This is essential for dynamic orchestration: toggling `noop` status, swapping runtimes, or updating (de)serializers before a build.

- **`node_meta_lens(node_name, field)`**: Targets the configuration of a node.
- **Fields**: `"runtime"`, `"noop"`, `"serializer"`, `"deserializer"`.

```t
p = pipeline {
    data_gen = node(command = <{ [1, 2, 3, 4] }>)
    model_r  = node(data_gen, command = <{ train(data_gen) }>, runtime = R)
}

-- Surgical update: toggle 'noop' status to skip computation
noop_l = node_meta_lens("model_r", "noop")
p_noop = p |> set(noop_l, true)

-- Re-orchestration: Swap a node's runtime to Python
p_py = p |> set(node_meta_lens("model_r", "runtime"), "Python")
```

### 8. Pipeline Traversals: Querying Node Metadata

`filter_lens` also works on a **Pipeline**. In that case the predicate does **not** receive the node value directly; it receives a metadata `Dict` built from the pipeline definition.

The fields currently exposed are:

- `name`
- `runtime`
- `serializer`
- `deserializer`
- `noop`
- `deps`
- `depth`
- `command_type`

`get(p, filter_lens(...))` returns the **matched node values**. The predicate only uses metadata to decide which nodes to keep.

```t
-- All R nodes
r_nodes_l = filter_lens(\(meta) meta.runtime == "R")
get(p, r_nodes_l)

-- Nodes that will actually run
active_nodes_l = filter_lens(\(meta) meta.noop == false)
get(p, active_nodes_l)

-- Root nodes only
root_nodes_l = filter_lens(\(meta) meta.depth == 0)
get(p, root_nodes_l)

-- Nodes using a specific serializer
pmml_nodes_l = filter_lens(\(meta) meta.serializer == "pmml")
get(p, pmml_nodes_l)

-- Script-backed nodes only
script_nodes_l = filter_lens(\(meta) meta.command_type == "script")
get(p, script_nodes_l)
```

If you want to inspect the metadata rows themselves rather than the node values, use the same predicate against `pipeline_to_frame(p)`:

```t
pipeline_to_frame(p) |> filter(\(row) row.runtime == "R")
pipeline_to_frame(p) |> filter(\(row) row.depth <= 1 and row.noop == false)
```

#### Querying diagnostics and errored nodes

Errors are **not** part of the metadata dictionary exposed by `filter_lens` on a raw `Pipeline`. Diagnostics live in `read_pipeline(p)`, so filter those records instead:

```t
-- Lowest-level lens form
pipe_info = read_pipeline(p)

errored_nodes_l = compose(
  col_lens("nodes"),
  filter_lens(\(node) !is_na(node.diagnostics.error))
)

healthy_nodes_l = compose(
  col_lens("nodes"),
  filter_lens(\(node) is_na(node.diagnostics.error))
)

get(pipe_info, errored_nodes_l)
get(pipe_info, healthy_nodes_l)
```

If you only want the filtered node records and do not need to compose a larger lens pipeline, prefer the higher-level wrapper:

```t
which_nodes(p, !is_na(diagnostics.error))
errored_nodes(p)
```

For a quick summary, `read_pipeline(p).diagnostics.error_nodes` gives you just the names of nodes that errored.

### 9. Serialization & Multi-Node Safety

T lenses are fully serializable. This means you can define a complex `FilterLens` in one pipeline node, pass it as a parameter to another node (even one running in a different runtime like R or Python), and it will maintain its structure.

```t
-- Node A: Define a "quality control" lens
qc_lens = filter_lens(\(r) r.std_err > 0.05)

-- Node B: Receives qc_lens as an argument and applies it to its local data
flagged_data = data |> over(qc_lens, \(v) v + " [NEEDS REVIEW]")
```

---

### 10. API Quick Reference

| Function | Signature | Use Case |
| :--- | :--- | :--- |
| **`set(data, lens, value)`** | `(A, Lens, B) -> A` | Replaces the focused value. |
| **`over(data, lens, f)`** | `(A, Lens, B -> B) -> A` | Transforms the focused value. |
| **`modify(data, lens1, f1, ...)`** | `(A, Lens, B -> B, ...) -> A` | Multiple lens+function pairs in one call. |
| **`compose(...)`** | `(...Lens) -> Lens` | Chains any number of lenses into one path. |
| **`col_lens(name)`** | `String -> Lens` | Column/key/field focus. |
| **`node_lens(name)`** | `String -> Lens` | Pipeline node result focus. |
| **`node_meta_lens(n, f)`**| `(String, String) -> Lens` | Pipeline node metadata focus. |
| **`env_var_lens(n, v)`** | `(String, String) -> Lens` | Pipeline env var focus. |
| **`idx_lens(i)`** | `Int -> Lens` | List/Vector index focus. |
| **`row_lens(i)`** | `Int -> Lens` | DataFrame row focus. |
| **`filter_lens(p)`** | `Function -> Traversal` | Condition-based multi-focus (Lists, Vectors, DataFrames, Pipelines). |

---

### Best Practices

1. **Name your paths**: Store commonly used lenses as named variables (`pct_l`, `salary_l`) and reuse them across `get`, `set`, and `over` calls.
2. **Encapsulation**: When building packages, export lenses for your internal data structures so users can extend your logic without knowing column names.
3. **Prefer standard verbs for flat DataFrames**: Lenses shine in nested or polymorphic contexts. For straightforward flat-DataFrame operations, `mutate()` and `filter()` are simpler and more idiomatic.
4. **Vectorize Early**: If your function inside `over` works on a Vector, use broadcasting operators (`.+`, `.*`) to ensure performance.


# FILE: docs/quotation.md

# Metaprogramming: Quotation and Quasiquotation

T provides powerful metaprogramming capabilities inspired by Lisp and R's `rlang` package. These features allow you to capture code as data, manipulate it, and evaluate it dynamically.

## Core Concepts

- **Quotation**: Capturing an expression without evaluating it immediately.
- **Quosure**: A quoted expression paired with its lexical environment (like R's `rlang::quo`).
- **Unquoting**: Selectively evaluating parts of a quoted expression.
- **Splicing**: Expanding a list or collection into multiple arguments or elements within a quoted expression.
- **Symbols**: Representing names (identifiers) as data.

## Capturing Code: `expr` vs `quo`

T has two families of quotation functions, matching R's `rlang`:

| Function | Result | Environment | Use when… |
|----------|--------|-------------|-----------|
| `expr(x)` | `Expression` | None | You only need the AST |
| `quo(x)` | `Quosure` | Captured at call site | You need the AST + its lexical context |
| `exprs(...)` | `List[Expression]` | None | Multiple naked expressions |
| `quos(...)` | `List[Quosure]` | Captured at call site | Multiple expressions with lexical context |

### `expr(expression)`

The `expr()` function captures the code as a naked **Expression** object. The current environment is *not* stored.

```t
e = expr(1 + 2)
print(e)
-- Output: expr(1 + 2)
```

### `quo(expression)`

The `quo()` function captures the code as a **Quosure** — a pair of the expression and its lexical environment. When later evaluated with `eval()`, the expression runs in the captured environment, not the caller's.

```t
x = 10
q = quo(1 + x)   -- captures x = 10 in the environment
x = 99
eval(q)           -- returns 11, not 100
```

### `exprs(...)`

`exprs()` captures multiple expressions and returns them as a list of naked Expression objects. It supports named arguments.

```t
ee = exprs(x = 1 + 1, y = 2 + 2)
-- Result: [x: expr(1 + 1), y: expr(2 + 2)]
```

### `quos(...)`

`quos()` captures multiple expressions as a list of Quosures, each paired with the current lexical environment.

```t
x = 10
qs = quos(a = 1 + x, b = 2 * x)
-- Result: [a: quo(1 + x), b: quo(2 * x)]
-- Both quosures capture x = 10 in their environment.
```

### Symbols and Bare Words

In T, if you use a word that isn't defined as a variable, it is automatically treated as a **Symbol** when inside a quoting context. This is useful for building Domain Specific Languages (DSLs).

```t
e = expr(select(df, age, height))
-- 'select', 'age', and 'height' are captured as symbols.
```

## Evaluating Code

### `eval(expr_or_quosure)`

The `eval()` function evaluates an Expression or Quosure:
- **Expression**: evaluated in the *current* environment.
- **Quosure**: evaluated in its *captured* environment.

```t
e = expr(10 + 20)
eval(e)          -- evaluates in current env → 30

x = 5
q = quo(x + 1)   -- captures x = 5
x = 100
eval(q)          -- evaluates in captured env (x = 5) → 6
```

### Dynamic Lookup: `get(name)`

The `get()` function provides a way to retrieve a variable's value dynamically by its name (as a String or Symbol). This matches R's `get()` semantics and is useful when you have a variable name stored in a string.

```t
salary = [1000, 2000, 3000]
var_name = "salary"

get(var_name)       -- retrieves [1000, 2000, 3000]
get(sym(var_name))  -- also works with Symbols
```

Important: `get()` resolves names in the **calling environment**, not in a data-masking context. To retrieve a column dynamically inside a data verb, use quasiquotation with `!!sym(col)`.

## Quasiquotation

Quasiquotation allows you to "fill in the blanks" in a captured expression.

### `!!` (Unquote)

The `!!` (pronounced "bang-bang") operator evaluates its operand immediately and injects the result into the surrounding quoted expression. When the operand is a Quosure, only the expression part is injected (the environment is stripped).

```t
x = 10
e = expr(1 + !!x)
print(e) 
-- Output: expr(1 + 10)
```

```t
inner = quo(1.5 + 2.5)
outer = expr(2 * !!inner)   -- !! strips env from quosure
print(outer)
-- Output: expr(2 * (1.5 + 2.5))
```

### `!!!` (Unquote-Splice)

The `!!!` (pronounced "triple-bang") operator evaluates its operand and **splices** the elements into the surrounding call or list. The operand must evaluate to a `List`, `Vector`, or `Dict`. Quosures in the spliced list have their environments stripped.

#### Splicing into Arguments

```t
vals = [1, 2, 3]
e = expr(sum(!!!vals))
print(e)
-- Output: expr(sum(1, 2, 3))
```

#### Splicing with Names

If you splice a named List, the names are used as argument names in the resulting call.

```t
my_args = [x: 10, y: 20]
e = expr(f(!!!my_args, z: 30))
print(e)
-- Output: expr(f(x = 10, y = 20, z = 30))
```

### `!!name := value` (Dynamic Naming)

The `!!name := value` syntax allows you to use a dynamically computed string or symbol as the name of an argument or list element inside a quoting context. The left-hand side (`name`) must evaluate to a `String` or `Symbol`.

```t
col = "age"
e = expr(mutate(df, !!col := 42))
print(e)
-- Output: expr(mutate(df, age = 42))
```

If `!!name` does not evaluate to a `String` or `Symbol`, a `TypeError` is raised.

### `sym(string_or_symbol)`

When you have a column or argument name in a string variable, use `sym()` to turn it into a runtime `Symbol` that can be injected with `!!`.

```t
col_name = "mpg"
expr(select(df, !!sym(col_name)))
-- Output: expr(select(df, mpg))
```

This is most useful for programmatic code generation. Use `sym()` to turn a string into a label that `!!` can inject as a symbol, or that `get()` can use for variable lookup.

## Non-Standard Evaluation (NSE)

For writing functions that accept unevaluated expressions from the caller — similar to `dplyr` verbs in R — T provides `enquo()` and `enquos()`.

### `enquo(param)`

`enquo()` must be called inside a function body. It captures the **expression AND the caller's environment** for the named argument `param`, returning a Quosure. This is the quosure equivalent of `enquo()` in R's rlang.

```t
my_select = \(df: DataFrame, col: Any -> DataFrame) {
  col_expr = enquo(col)           -- captures expr + caller's env
  eval(expr(df |> select(!!col_expr)))
}

my_select(iris, $Sepal.Length)
-- Equivalent to: iris |> select($Sepal.Length)
```

`enquo()` accepts exactly one argument, which must be a bare symbol (the name of one of the function's parameters).

### Auto-Quoted Parameters: `\(df, $col)`

T now supports auto-quoting directly in lambda and `function(...)` parameter lists. Prefixing a parameter with `$` means the caller can pass a bare column name and the function receives it as a symbol-like column reference.

```t
my_mean = \(df, $col) {
  summarize(df, result = mean(!!col))
}

df = dataframe([salary: [100, 200, 300]])
my_mean(df, salary)
```

This removes the need for the common `enquo()` + `eval(expr(...))` wrapper when the function is simply forwarding a column-like argument into an NSE-aware data verb.

Current behavior:

- callers can pass a bare name like `salary`
- callers can still pass `$salary`
- string and symbol values are also accepted
- the captured parameter evaluates to a `Symbol` in ordinary code
- `!!col` inside NSE-aware verbs expands back to a column reference so `summarize(result = mean(!!col))` works as expected

Use `enquo()` when you need to preserve the caller's full expression rather than just a column-style name.

### `enquos(...)`

`enquos()` is the variadic counterpart to `enquo()`. It captures all expressions passed through the variadic `...` parameter as a named list of Quosures, each paired with the caller's environment.

```t
my_summarize = \(df: DataFrame, ... -> DataFrame) {
  cols = enquos(...)              -- list of quosures from the caller
  eval(expr(df |> summarize(!!!cols)))
}

my_summarize(iris,
  mean_sepal = mean($`Sepal.Length`),
  mean_petal = mean($`Petal.Length`))
-- Evaluates to: iris |> summarize(mean_sepal = ..., mean_petal = ...)
```

`enquos()` is called with `...` or with no arguments; both capture the variadic expressions from the enclosing call.

## Advanced Examples

### Dynamic Pipeline Generation

You can use quasiquotation to dynamically build pipeline nodes or intents:

```t
var_name = "mpg"
my_intent = expr(intent {
  target = !!var_name
  method = "lm"
})

print(my_intent)
-- Output: expr(intent { target = "mpg"; method = "lm" })
```

### Prefix-Call Syntax

T also supports a Lisp-style prefix call syntax which integrates seamlessly with quotation:

```t
e = expr((add, 1, 2))
-- Equivalent to expr(add(1, 2))
```

## Summary of Operators

| Operator/Function | Purpose |
| :--- | :--- |
| `expr(x)` | Capture `x` as a naked Expression (no environment). |
| `exprs(...)` | Capture multiple expressions as a List of naked Expressions. |
| `quo(x)` | Capture `x` as a Quosure (expression + lexical environment). |
| `quos(...)` | Capture multiple expressions as a List of Quosures. |
| `eval(e)` | Evaluate Expression `e` in the current env, or Quosure `e` in its captured env. |
| `get(name)` | Dynamically retrieve a variable's value by String or Symbol name. |
| `sym(s)` | Convert a String `s` into a Symbol at runtime. |
| `!!x` | Evaluate `x` and inject into `expr()`/`quo()`; strips env from quosures. |
| `!!!x` | Evaluate `x` and splice elements into `expr()`/`quo()`. |
| `!!name := value` | Use a dynamic String/Symbol as an argument name inside `expr()`/`quo()`. |
| `enquo(param)` | Inside a function: capture caller's expression for `param` as a Quosure. |
| `enquos(...)` | Inside a function: capture all variadic expressions as a List of Quosures. |

## Data Masking & Column Resolution

When an Expression or Quosure is evaluated inside a data verb (like `mutate`, `filter`, or `summarize`), it uses a **Data Mask**.

T handles column resolution using a specific prefixing logic to avoid collisions with global functions:

1.  **Prefix `$`: ** Expressions like `$score` are parsed as `ColumnRef`. 
2.  **Resolution Priority:**
    - The evaluator first checks the environment for a key named `$score`.
    - Data verbs automatically populate the environment with both the plain name (`score`) and the prefixed name (`$score`) for every column in the current DataFrame.
    - If a plain variable `score` is defined in the global environment (e.g., as a function), it does **not** interfere with `$score`.

### Example: Avoiding Collisions

```t
-- Global 'score' function
score = \(x, y) x + y

df = [score: 1, 2, 3]

-- This works correctly because '$score' looks for '$score' in the mask,
-- ignoring the global 'score' function.
df |> mutate(new = $score * 2)
```

## Best Practices

1.  **Use `quo` by default**: When in doubt, use `quo` instead of `expr`. It ensures the code "remembers" its environment, preventing `NameError` when evaluated in different contexts.
2.  **Quotation in Functions**: Use `$param` for the common "accept a column name" case. Use `enquo` when you need the caller's full expression, and use `sym()` when you are starting from a computed string.
3.  **Dynamic Naming**: Use `!!name := !!value` for maximum flexibility when writing generic data processing functions.


# FILE: docs/llm-collaboration.md

# LLM Collaboration with T

How T enables structured, auditable collaboration between humans and Large Language Models for data analysis.

## The LLM Code Generation Problem

Current LLM-assisted coding suffers from:

- **Opaque Generation**: LLMs generate complete scripts without structure
- **Context Loss**: Assumptions and constraints are implicit
- **Brittle Regeneration**: Changing one requirement breaks everything
- **No Audit Trail**: Hard to verify what LLM understood
- **Global Changes**: LLMs rewrite entire files instead of localized edits

**Result**: LLM-generated code is useful for prototyping but hard to maintain, audit, or regenerate.

---

## T's LLM-Native Design

T treats LLMs as **first-class collaborators** with structured boundaries:

### Key Principles

1. **Intent over Implementation**: Humans specify goals, LLMs generate code
2. **Local over Global**: LLMs generate pipeline nodes, not entire scripts
3. **Inspectable over Opaque**: Intent blocks make assumptions explicit
4. **Regenerable over Brittle**: Stable boundaries enable safe code updates

---

## Intent Blocks

Intent blocks are **machine-readable metadata** that capture analytical goals.

### Basic Intent

```t
intent {
  description: "Analyze customer churn patterns by age group",
  goal: "Identify age ranges with highest churn risk"
}

-- Analysis code follows...
```

### Comprehensive Intent

```t
intent {
  -- High-level description
  description: "Customer lifetime value segmentation",
  goal: "Segment customers into value tiers for targeted marketing",
  
  -- Data specifications
  data_source: "customers.csv from CRM export 2023-12-31",
  required_columns: ["customer_id", "total_spend", "purchase_count", "signup_date"],
  
  -- Analytical assumptions
  assumptions: [
    "Churn defined as no purchase in 90 days",
    "LTV calculated as total_spend / months_active",
    "Test accounts excluded"
  ],
  
  -- Business constraints
  constraints: [
    "Minimum 50 customers per segment",
    "Segment labels: high_value, medium_value, low_value",
    "Thresholds: high > $1000, medium > $500"
  ],
  
  -- Data quality rules
  validation: [
    "total_spend > 0",
    "purchase_count > 0",
    "signup_date between 2020-01-01 and 2023-12-31"
  ],
  
  -- Expected outputs
  outputs: [
    "customer_segments.csv with columns: customer_id, segment, ltv",
    "segment_summary.csv with counts and average LTV per segment"
  ],
  
  -- Metadata
  created: "2024-01-15",
  author: "Marketing Team",
  llm_assistant: "GPT-4",
  version: "1.0"
}

-- LLM generates implementation based on intent
analysis = pipeline {
  raw = read_csv("customers.csv", clean_colnames = true)
  
  validated = raw
    |> filter($total_spend > 0)
    |> filter($purchase_count > 0)
  
  with_ltv = validated
    |> mutate($ltv, \(row) row.total_spend / months_since(row.signup_date))
  
  segmented = with_ltv
    |> mutate($segment, \(row)
        if (row.ltv > 1000) "high_value"
        else if (row.ltv > 500) "medium_value"
        else "low_value"
      )
  
  summary = segmented
    |> group_by($segment)
    |> summarize($count = nrow($segment), $avg_ltv = mean($ltv))
}

write_csv(analysis.segmented, "customer_segments.csv")
write_csv(analysis.summary, "segment_summary.csv")
```

**Benefits**:
- LLM understands exact requirements
- Human can verify LLM understood correctly
- Future LLMs can regenerate code from intent
- Intent serves as documentation
- Changes to intent are versioned (Git)

---

## Local Code Generation

Instead of generating entire scripts, LLMs generate **pipeline nodes**.

### Traditional LLM Workflow (Problematic)

**Human prompt**: "Analyze sales by region"

**LLM generates** (entire script):
```python
import pandas as pd

df = pd.read_csv("sales.csv")
df = df[df['amount'] > 0]
df_grouped = df.groupby('region')['amount'].sum()
df_grouped = df_grouped.sort_values(ascending=False)
print(df_grouped)
```

**Problems**:
- If requirements change, LLM rewrites everything
- No separation between data loading, cleaning, analysis
- Hard to modify one step without breaking others

### T LLM Workflow (Structured)

**Human writes intent**:
```t
intent {
  description: "Sales analysis by region",
  steps: {
    load: "Load sales.csv",
    clean: "Remove zero/negative amounts",
    analyze: "Sum revenue by region, sort descending"
  }
}
```

**LLM generates pipeline nodes**:
```t
analysis = pipeline {
  -- Node 1: Load (stable)
  raw = read_csv("sales.csv")
  
  -- Node 2: Clean (can regenerate independently)
  cleaned = raw |> filter($amount > 0)
  
  -- Node 3: Analyze (can regenerate independently)
  by_region = cleaned
    |> group_by($region)
    |> summarize($total = sum($amount))
    |> arrange($total, "desc")
}
```

**Benefits**:
- **Change request**: "Also filter by date"
  - LLM only regenerates `cleaned` node
  - `raw` and `by_region` unchanged
- **Local reasoning**: Each node is independently understandable
- **Cacheable**: Unchanged nodes don't re-execute

---

## LLM Workflow Patterns

### Pattern 1: Intent-Driven Generation

**Step 1**: Human writes intent
```t
intent {
  description: "Customer cohort analysis",
  cohort_definition: "First purchase month",
  metric: "Average order value by cohort",
  timeframe: "2023-01-01 to 2023-12-31"
}
```

**Step 2**: LLM generates implementation
```t
cohort_analysis = pipeline {
  orders = read_csv("orders.csv")
  -- LLM fills in details based on intent
}
```

**Step 3**: Human reviews, provides feedback
```
"Include only completed orders"
```

**Step 4**: LLM updates (localized change)
```t
  cleaned = orders |> filter($status == "completed")
```

### Pattern 2: Explain and Generate

**Step 1**: Human provides data sample
```t
sample = read_csv("data.csv")
explain(sample)
-- DataFrame(100 rows x 5 cols: [date, product, region, quantity, price])
```

**Step 2**: Human requests analysis
```
"Calculate total revenue by product, show top 10"
```

**Step 3**: LLM generates with intent
```t
intent {
  description: "Top 10 products by revenue",
  data: "data.csv with date, product, region, quantity, price",
  computation: "revenue = quantity * price, group by product, sort descending, top 10"
}

top_products = sample
  |> mutate($revenue = $quantity * $price)
  |> group_by($product)
  |> summarize($total_revenue = sum($revenue))
  |> arrange($total_revenue, "desc")
  |> head(10)
```

### Pattern 3: Iterative Refinement

**Iteration 1**: Basic implementation
```t
intent { description: "Average sales by month" }

monthly = sales |> group_by($month) |> summarize($avg = mean($amount))
```

**Iteration 2**: Add NA handling
```t
intent { 
  description: "Average sales by month",
  requirements: "Handle missing amounts"
}

monthly = sales |> group_by($month) |> summarize($avg = mean($amount))
```

**Iteration 3**: Add validation
```t
intent { 
  description: "Average sales by month",
  requirements: "Handle missing amounts, exclude zero sales"
}

monthly = sales
  |> filter($amount > 0)
  |> group_by($month)
  |> summarize($avg = mean($amount))
```

**Each iteration**: Intent updated, LLM regenerates, human verifies.

---

## Introspection for LLMs

T provides introspection functions for LLM context:

### Explain Data

```t
df = read_csv("customers.csv")
explain(df)
-- "DataFrame(1000 rows x 5 cols: [id, name, age, city, ltv])"

-- JSON format for LLM consumption
explain_json(df)
-- {"type": "DataFrame", "rows": 1000, "columns": [...], "sample": [...]}
```

### Intent Fields

```t
i = intent { description: "Analysis", goal: "Insights" }

intent_fields(i)
-- {description: "Analysis", goal: "Insights"}

intent_get(i, "description")
-- "Analysis"
```

### Pipeline Introspection

```t
p = pipeline {
  x = 10
  y = x * 2
  z = y + 5
}

pipeline_nodes(p)
-- ["x", "y", "z"]

pipeline_deps(p, "z")
-- ["y"]

-- LLM can understand dependency graph
```

---

## LLM Best Practices

### For Humans

1. **Write Intent First**: Specify goals before code
2. **Be Specific**: Include assumptions, constraints, expected outputs
3. **Review Generated Code**: Verify LLM understood correctly
4. **Iterate Locally**: Request changes to specific nodes, not entire scripts
5. **Version Intents**: Track intent changes in Git

### For LLMs

1. **Parse Intent**: Extract requirements from intent block
2. **Generate Pipelines**: Use pipeline structure for modularity
3. **Include Error Handling**: Use `na_rm`, validation checks
4. **Preserve Intents**: Keep intent blocks in generated code
5. **Explain Assumptions**: Document why specific approaches were chosen

---

## Example: Full LLM Collaboration

**Human**: "I need to analyze employee salaries by department and identify outliers"

**LLM Response**:
```t
intent {
  description: "Employee salary analysis with outlier detection",
  
  data_source: "employees.csv",
  required_columns: ["employee_id", "department", "salary"],
  
  analysis_steps: [
    "Calculate statistics by department (mean, SD)",
    "Identify outliers (>2 SD from department mean)",
    "Generate summary report"
  ],
  
  outlier_definition: "Salary > department_mean + 2*department_sd",
  
  outputs: [
    "department_stats.csv: mean, sd, count per department",
    "outliers.csv: employees with salaries > 2 SD from mean"
  ],
  
  created: "2024-01-15",
  llm_assistant: "Claude"
}

salary_analysis = pipeline {
  -- Load data
  employees = read_csv("employees.csv", clean_colnames = true)
  
  -- Department statistics
  dept_stats = employees
    |> group_by($department)
    |> summarize($mean_salary = mean($salary), $sd_salary = sd($salary), $count = nrow($department))
  
  -- Identify outliers
  -- (Join would be manual or use a join function if available)
  -- For now, calculate globally
  overall_mean = mean(employees.salary, na_rm = true)
  overall_sd = sd(employees.salary, na_rm = true)
  threshold = overall_mean + 2 * overall_sd
  
  outliers = employees
    |> filter($salary > threshold)
    |> select($employee_id, $department, $salary)
}

-- Export results
write_csv(salary_analysis.dept_stats, "department_stats.csv")
write_csv(salary_analysis.outliers, "outliers.csv")

print("Analysis complete:")
print("Department stats: department_stats.csv")
print("Outliers: outliers.csv")
```

**Human Review**: "Good! But I want outliers per department, not overall"

**LLM Update** (regenerates `outliers` node):
```t
  -- Update: Per-department outliers
  with_dept_stats = employees
    |> group_by($department)
    |> mutate($dept_mean, \(g) mean(g.salary, na_rm = true))
    |> mutate($dept_sd, \(g) sd(g.salary, na_rm = true))
  
  outliers = with_dept_stats
    |> filter($salary > $dept_mean + 2 * $dept_sd)
    |> select($employee_id, $department, $salary, $dept_mean, $dept_sd)
```

**Note**: Only `outliers` node changed; `dept_stats` and `employees` nodes unchanged.

---

## Audit Trail

Intent blocks + version control = complete audit trail:

```bash
git log --oneline intent_blocks/

abc123 Update: Exclude test accounts from churn analysis
def456 Add validation: minimum transaction amount $1
789ghi Initial: Customer churn analysis

git show abc123:src/pipeline.t
# Shows exactly what assumptions changed and why
```

---

**See Also**:
- [Reproducibility](reproducibility.md) — Nix for reproducible environments
- [Examples](examples.md) — Intent-driven analysis examples
- [Pipeline Tutorial](pipeline_tutorial.md) — Pipeline structure


# FILE: docs/package_development.md

# T Package Development Guide

This guide walks you through creating, developing, and publishing a package for the T language.

## 1. Creating a Package

You can create a new package interactively using the `t init --package` command.

```bash
$ t init --package advanced-stats
Initializing new T package...
Author [User]: Alice
License [EUPL-1.2]: EUPL-1.2

✓ Package 'advanced-stats' created successfully!
```

This creates a standard directory structure:

- **DESCRIPTION.toml**: Package metadata and dependencies.
- **flake.nix**: Reproducible development environment definition.
- **README.md**: Package overview.
- **CHANGELOG.md**: History of changes.
- **LICENSE**: License text.
- **src/**: Source code (e.g., `main.t`).
- **tests/**: Test files (e.g., `test-advanced-stats.t`).
- **examples/**: Usage examples.
- **docs/**: Documentation (e.g., `index.md`).

## 2. Managing Dependencies

Dependencies are declared in `DESCRIPTION.toml`. To add a dependency on another T package (e.g., `math` or a git repository):

```toml
[dependencies]
# Example: depend on a git repository
my-lib = { git = "https://github.com/user/my-lib", tag = "v1.0.0" }
```

### 2.1 System Tools and LaTeX

You can also declare system-level tools and LaTeX packages required for your package development or documentation.

#### Additional Development Tools

Under `[additional-tools]`, you can add any package from Nixpkgs. These tools will be available in your `nix develop` shell:

```toml
[additional-tools]
# Tools for building, documenting, or testing your package
packages = ["git", "jq", "gawk", "pandoc"]
```

#### LaTeX for Documentation

If your documentation requires LaTeX (e.g., for formulas), use the `[latex]` section. T provides `texlive` based on `scheme-small`. You only need to list additional packages:

```toml
[latex]
# LaTeX packages for math formulas or advanced formatting
packages = ["amsmath", "blindtext", "physics"]
```

After modifying dependencies or updating the `[additional-tools]` or `[latex]` sections, run `t update` to sync your `flake.nix` and lock file:

```bash
$ t update
Syncing 1 dependency(ies) from DESCRIPTION.toml → flake.nix...
Running nix flake update...
```

This regenerates `flake.nix` so new dependencies appear as proper flake inputs, then locks them. After updating, re-enter the development shell:

```bash
$ nix develop
```

## 3. Writing Code

Write your T code in `src/`. For example, `src/stats_helpers.t`:

```t
-- src/stats_helpers.t

-- Public by default — importers can use this
weighted_mean = \(x, w) sum(x .* w) / sum(w)

--# Internal helper, not for public use.
--# @private
_validate_weights = \(w) {
  assert(length(w) > 0)
}
```

All top-level bindings in your package are **public by default**. To hide an internal helper, add `@private` to its T-Doc block.

You can test your code interactively in the REPL:

```bash
$ t repl
T> import "src/stats_helpers.t"
T> weighted_mean([1, 2, 3], [0.5, 0.3, 0.2])
1.7
```

## 4. Testing

T has a built-in test runner. Tests are `.t` files in the `tests/` directory.

Example `tests/test-mean.t`:

```t
import "src/stats.t"

assert(stats.mean([1, 2, 3]) == 2.0)
assert(stats.mean([-1, -1]) == -1.0)
```

Run all tests with:

```bash
$ t test
```

## 5. Documentation

T packages use **T-Doc**, a comment-based documentation system. Documentation lives in source files close to the code and is generated into Markdown.

### Writing Documentation

Use `--#` comments above your functions to document them.

```t
--# Calculate the square of a number.
--#
--# @param x :: Integer
--#   The input number.
--#
--# @return :: Integer
--#   The squared result.
--#
--# @example
--#   square(4)
--#   -- 16
--#
--# @export
fn square(x) {
  x * x
}
```

**Supported Tags:**
- `@param <name> :: <type> <description>`: Document a parameter.
- `@return :: <type> <description>`: Document the return value.
- `@example`: Start a code example block.
- `@seealso <func1>, <func2>`: Link to related functions.
- `@family <name>`: Group related functions together.
- `@private`: Mark the function as private — it will not be visible to importers.
- `@export`: Explicitly mark as public (this is the default, so usually not needed).

### Generating Documentation

To generate the documentation files in `docs/reference/`:

```bash
$ t doc --parse --generate
```

This will:
1.  Scan your `src/` directory for `--#` blocks.
2.  Generate Markdown files for each function in `docs/reference/`.
3.  Generate a `docs/reference/index.md` listing all exported functions.

### Viewing Documentation

You can view your documentation locally using:

```bash
$ t docs
```
This opens `docs/index.md` (or `README.md`) in your system viewer. You can link to your reference documentation from there.

## 6. Quality Control

Before publishing, run `t doctor` to check your package for common issues:

```bash
$ t doctor
✓ Everything looks good!
```

It checks for:
- Required files (`DESCRIPTION.toml`, `flake.nix`).
- Valid directory structure.
- Documentation existence.
- Nix installation.

## 7. Publishing

When you are ready to release a version:

1.  Ensure `DESCRIPTION.toml` has the correct `version`.
2.  Update `CHANGELOG.md` with release notes for that version.
3.  Commit all changes to git.
4.  Run `t publish`.

```bash
$ t publish
Preparing to publish version 0.1.0...

✓ Validation complete.
Proceed to tag and push v0.1.0? [y/N] y
✓ Tag v0.1.0 pushed to remote.
```

This will run your tests, verify the changelog, and push a git tag to your repository.

## 8. How Others Import Your Package

Once published, other packages or projects can depend on yours by adding it to their `DESCRIPTION.toml` or `tproject.toml`:

```toml
[dependencies]
advanced-stats = { git = "https://github.com/user/advanced-stats", tag = "v0.1.0" }
```

Then in their T code, they can import your package:

```t
-- Import everything (all public functions)
import advanced_stats

-- Import only specific functions
import advanced_stats[weighted_mean]

-- Import with aliases
import advanced_stats[wmean=weighted_mean]
```

Functions marked with `@private` in your package are not visible to importers.

---

## Next Steps

Now that you know how to build packages, explore how to ensure your work is reproducible and understand T's underlying architecture:

1. **[Reproducibility Guide](reproducibility.md)** — Deep dive into T's commitment to reproducible research.
2. **[Architecture](architecture.md)** — Understand the internal design and execution model of T.
3. **[Project Development](project_development.md)** — Master T's project structure and dependency management.
4. **[API Reference](api-reference.md)** — Complete function reference by package.


# FILE: docs/project_development.md

# T Project Development Guide

This guide walks you through creating and developing a **T project** — a data analysis project that uses T packages.

> **Package vs Project**: A *package* is a reusable library of T functions. A *project* is a data analysis workspace that depends on packages.

## 1. Creating a Project

Create a new project interactively:

```bash
$ t init --project housing-analysis
Initializing new T project...
Author [User]: Alice
License [EUPL-1.2]: EUPL-1.2
Nixpkgs date [2026-02-19]: 2026-02-19

✓ Project 'housing-analysis' created successfully!
```

This creates the following structure:

- **tproject.toml**: Project metadata and dependencies.
- **flake.nix**: Reproducible environment definition.
- **README.md**: Project documentation.
- **.gitignore**: Git exclusion list.
- **src/**: Your analysis scripts (e.g., `pipeline.t`).
- **data/**: Data files.
- **outputs/**: Output directory for results.
- **tests/**: Project-specific tests.

## 2. Entering the Development Environment

Projects use Nix for reproducibility. Enter the development shell:

```bash
$ nix develop
```

This ensures all dependencies (T, packages, R, Nix) are available at the exact versions specified in `flake.lock`.

## 3. Adding Dependencies

Dependencies on T packages are declared in `tproject.toml`:

```toml
[project]
name = "housing-analysis"
description = "Analyzing housing data with T"

[dependencies]
my_stats = { git = "https://github.com/user/my-stats", tag = "v0.1.0" }
data_utils = { git = "https://github.com/user/data-utils", tag = "v0.2.0" }

[t]
min_version = "0.51.4"
```

### 3.1 System Dependencies and LaTeX

Beyond T packages, you can declare system-level tools and LaTeX packages required for your project.

#### Additional Tools

Use the `[additional-tools]` section to add any package from Nixpkgs (e.g., CLI utilities, compilers, or libraries):

```toml
[additional-tools]
# These will be available in your 'nix develop' shell and pipeline sandboxes
packages = ["git", "jq", "gawk", "pandoc"]
```

#### LaTeX Support

If your project involves generating PDFs or reports, use the `[latex]` section. T automatically provides a `texlive` environment starting from `scheme-small`. Just list any additional LaTeX packages you need:

```toml
[latex]
# Standard LaTeX packages
packages = ["amsmath", "blindtext", "physics", "hyperref"]
```

After adding or changing dependencies (including `[additional-tools]` or `[latex]` sections), run:

```bash
$ t update
Syncing 2 dependency(ies) from tproject.toml → flake.nix...
Running nix flake update...
```

This regenerates `flake.nix` so new dependencies and tools appear as proper flake inputs with locked versions. The tools will be available directly in your shell and automatically provided to any pipeline nodes (T, R, or Python) during execution. Then re-enter the shell:

```bash
$ nix develop
```

### 3.2 Upgrading T and Nixpkgs

To upgrade your project to the latest version of T and set the project's nixpkgs date to today's UTC date:

```bash
$ t upgrade
Checking for new T releases...
Upgrading project to T 0.51.1 and nixpkgs date 2026-03-21 (today's UTC date)...
Regenerating flake.nix and updating dependencies...
Running nix flake update...
```

This updates your `tproject.toml` and then runs `t update` automatically.

## 4. Importing Packages

Once inside `nix develop`, you can use the `import` statement in your T scripts to load package functions.

### Import All Public Functions

```t
import my_stats
```

This makes all public functions from `my_stats` available in scope.

### Import Specific Functions

```t
import my_stats[weighted_mean, correlation]
```

Only `weighted_mean` and `correlation` are imported.

### Import with Aliases

```t
import my_stats[wmean=weighted_mean, cor=correlation]
```

`weighted_mean` is available as `wmean`, `correlation` as `cor`.

### Visibility

All functions in a package are **public by default**. Package authors can mark internal helpers as private using `@private` in T-Doc comments — those functions will not be visible to importers.

## 5. Writing Analysis Scripts

Write your analysis in `src/`. For example, `src/pipeline.t`:

```t
import my_stats
import data_utils[read_clean]

p = pipeline {
  data = read_csv("data/housing.csv")
  clean = read_clean(data)
  avg_price = mean(clean.$price)
  price_by_area = clean |>
    group_by($area) |>
    summarize(avg=mean($price), sd=sd($price))
}

build_pipeline(p)
print(price_by_area)
```

Run your script:

```bash
$ t run src/pipeline.t
```

Or use the REPL for interactive exploration:

```bash
$ t repl
```

## 6. Running Tests

You can add tests in `tests/` following the same conventions as packages:

```t
-- tests/test-pipeline.t
import my_stats

result = weighted_mean([1, 2, 3], [0.5, 0.3, 0.2])
assert(result == 1.7)
```

Run them with:

```bash
$ t test
```

## 7. Reproducibility

Your project is fully reproducible through Nix:

- **`flake.nix`** declares exact dependency sources (managed by `t update`)
- **`flake.lock`** pins exact versions of all inputs
- **`tproject.toml`** is the human-readable source of truth for dependencies

Anyone can reproduce your environment:

```bash
$ git clone https://github.com/user/housing-analysis
$ cd housing-analysis
$ nix develop
$ t run src/pipeline.t
```

The same T version, same package versions, same R packages, and same system libraries are used every time.

## 8. IDE Support & Autocompletion

T projects are designed to work seamlessly with modern editors via the **Language Server Protocol (LSP)**.

### Using the LSP

The `t-lsp` binary is provided automatically by your project's `nix develop` shell. 

1.  Configure your editor (Vim, Emacs, or VS Code) once following the [Editor Support Guide](editors.md).
2.  Launch your editor *inside* the project directory after running `nix develop`.
3.  Alternatively, use **direnv** to automatically load the environment when you enter the project folder.

Once active, you will get real-time autocompletion for:
-   **Package functions**: Suggestions for all imported functions.
-   **Local variables**: Defined earlier in your script.
-   **DataFrame columns**: Column names from your data sources (accessible via the `$` prefix).

---

## Next Steps

1. **[Language Overview](language_overview.md)** — Learn about types, syntax, and logic.
2. **[Pipeline Tutorial](pipeline_tutorial.md)** — Learn how to structure your analysis as a DAG.
3. **[API Reference](api-reference.md)** — Explore the standard library.
4. **[Data Manipulation Examples](data_manipulation_examples.md)** — More worked examples of data wrangling.


# FILE: docs/editors.md

# Editor Support for T

This guide describes how to set up syntax highlighting and language server (LSP) features for the T programming language in various editors.

---

## Language Server Protocol (LSP)

The T language server provides advanced features like **Autocompletion** (context-aware suggestions), **Diagnostics** (real-time error checking), **Hover Information** (tooltips showing signatures/docs), and **Go to Definition**.

The `t-lsp` server is implemented in OCaml. When you enter a T project via `nix develop`, the correctly versioned binary is put in your `PATH`.

> [!IMPORTANT]
> **Launching the LSP**: For your editor to find the `t-lsp` binary, you must either launch your editor from **within** a `nix develop` shell, or use a tool like **[direnv](https://direnv.net/)** with `use flake` to automatically load the environment.

---

## Editor Configuration

### Shared tree-sitter grammar

T now ships a reusable tree-sitter grammar in `editors/tree-sitter-t`.
Only the source grammar, queries, metadata, and grammar tests are committed.
Generated parser sources are expected to be created locally when needed.

Install prerequisites and generate locally with:

```bash
cd /absolute/path/to/tlang/editors/tree-sitter-t
npx tree-sitter-cli generate
npx tree-sitter-cli test
```

If you prefer a global install instead of `npx`:

```bash
npm install --global tree-sitter-cli
cd /absolute/path/to/tlang/editors/tree-sitter-t
tree-sitter generate
tree-sitter test
```

This creates `src/parser.c`, `src/grammar.json`, `src/node-types.json`, and
`src/tree_sitter/` locally. Those files are ignored by Git and should not be
committed.

### VS Code / Positron

You can install the T language extension in two ways:

#### Option A: Download the `.vsix` file (Recommended)
1. Download the latest release: [`t-lang-0.51.0.vsix`](https://github.com/b-rodrigues/tlang/raw/main/editors/vscode/t-lang-0.51.0.vsix) (or download from the repository assets).
2. Install the extension using the command line:
   ```bash
   code --install-extension /path/to/downloaded/t-lang-0.51.0.vsix
   ```
   *Alternatively, in VS Code, go to the Extensions view, click the `...` menu, and select **Install from VSIX...***

#### Option B: From a cloned T repository
If you have already cloned the T repository locally:
```bash
code --install-extension editors/vscode/t-lang-0.51.0.vsix
```

#### Launching the Editor
Start VS Code or Positron from the same nix shell where you run `t`:
```bash
nix develop
code .
```

Once VS Code opens, we recommend opening the main entry point for your workspace:
- For **projects**: Open `src/pipeline.t`
- For **packages**: Open `src/main.t`

> **Tip**: You can use **Cmd+Enter** (macOS) or **Ctrl+Enter** (Linux/Windows) to send the current line or selection to the T REPL, exactly like in RStudio.

---

### Vim / Neovim

#### 1. Syntax Highlighting
Copy the support files into your `.vim` directory:
```bash
# Detect .t files
mkdir -p ~/.vim/ftdetect
cp editors/vim/ftdetect/t.vim ~/.vim/ftdetect/t.vim

# Syntax rules
mkdir -p ~/.vim/syntax
cp editors/vim/syntax/t.vim ~/.vim/syntax/t.vim
```

#### 2. LSP (via coc.nvim or nvim-lspconfig)

**For Vim (`coc.nvim`)**, add this to your `:CocConfig`:
```json
{
  "languageserver": {
    "tlang": {
      "command": "t-lsp",
      "filetypes": ["t"],
      "rootPatterns": ["tproject.toml", ".git"]
    }
  }
}
```

**For Neovim (`nvim-lspconfig`)**, add this to your `init.lua`:
```lua
local lspconfig = require('lspconfig')
local configs = require('lspconfig.configs')

if not configs.tlang then
  configs.tlang = {
    default_config = {
      cmd = { "t-lsp" },
      filetypes = {'t'},
      root_dir = lspconfig.util.root_pattern('tproject.toml', '.git'),
      settings = {},
    }
  }
end
lspconfig.tlang.setup{}
```

#### Tree-sitter highlighting in Neovim

```lua
local parser_config = require('nvim-treesitter.parsers').get_parser_configs()

parser_config.t = {
  install_info = {
    url = "/absolute/path/to/tlang/editors/tree-sitter-t",
    files = { "src/parser.c" },
    generate_requires_npm = true,
    requires_generate_from_grammar = true,
  },
  filetype = "t",
}

vim.treesitter.language.register("t", "t")
```

Then install it with `:TSInstallFromGrammar t`.
Replace `/absolute/path/to/tlang` with your local clone path.
If you already ran `npx tree-sitter-cli generate` locally, Neovim can reuse the
generated `src/parser.c`.

---

### Emacs

#### 1. Syntax Highlighting
Add the `editors/emacs/` directory to your `load-path` in `init.el`:
```elisp
(add-to-list 'load-path "/path/to/tlang/editors/emacs")
(require 't-mode)
```

#### 2. LSP (via eglot)
Add the following to your `init.el`:
```elisp
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(t-mode . ("t-lsp"))))

;; Automatically start eglot when opening a .t file
(add-hook 't-mode-hook 'eglot-ensure)
```

#### 3. Tree-sitter parser (Emacs 29+)

```elisp
(add-to-list 'treesit-language-source-alist
             '(t "/absolute/path/to/tlang/editors/tree-sitter-t"))

(unless (treesit-language-available-p 't)
  (treesit-install-language-grammar 't))
```
Replace `/absolute/path/to/tlang` with your local clone path.
Make sure the `tree-sitter` CLI is installed before running
`treesit-install-language-grammar`.

This makes the T parser available to `treesit`-aware packages and any custom
`t-ts-mode` built on top of the bundled grammar.

---

### Quarto

For literate programming with executable `{t}` chunks, add Quarto to your T project tools in `tproject.toml`:

```toml
[additional-tools]
packages = ["quarto"]
```

Then run `t update` and enter the project with `nix develop`. T will provision `_extensions/tlang` automatically. Enable the `tlang` filter in your document front matter:

```yaml
---
filters:
  - tlang
---
```

---

### Other tree-sitter editors

The same parser package can also be reused by editors that consume local
tree-sitter grammars, including:

- **Helix**
- **Zed**
- **Lapce**
- **Vim** setups that add tree-sitter through plugins

Point those editors at `editors/tree-sitter-t` and reuse the bundled query
files from `queries/`.

---

## Building from Source

If you are developing T itself, you can rebuild the LSP server with:
```bash
nix build .#default
```
The binary will be located at `result/bin/t-lsp`.


# FILE: docs/development.md

# Development Guide

Comprehensive guide for T language development, building, testing, and debugging.

## Table of Contents

- [Development Environment Setup](#development-environment-setup)
- [Building T](#building-t)
- [Testing](#testing)
- [Debugging](#debugging)
- [Development Workflow](#development-workflow)
- [Performance Profiling](#performance-profiling)
- [Common Tasks](#common-tasks)

---

## Development Environment Setup

### Prerequisites

1. **Nix** with flakes enabled (see [Installation Guide](installation.md))
2. **Git** for version control
3. **Editor** with OCaml support (VS Code, Emacs, Vim)

### Initial Setup

```bash
# Clone repository
git clone https://github.com/b-rodrigues/tlang.git
cd tlang

# Enter Nix development shell
nix develop

# Build
dune build

# Verify installation
dune exec src/repl.exe
```

### Editor Setup

#### VS Code

Install extensions:
- **OCaml Platform** (`ocamllabs.ocaml-platform`)
- **Dune** (syntax highlighting for `dune` files)

**`.vscode/settings.json`**:
```json
{
  "ocaml.sandbox": {
    "kind": "custom",
    "template": "nix develop --command $prog $args"
  }
}
```

#### Emacs

Use **Tuareg** mode and **Merlin**:

```elisp
;; In .emacs or init.el
(require 'tuareg)
(require 'merlin)
(add-hook 'tuareg-mode-hook #'merlin-mode)
```

#### Vim/Neovim

Use **Merlin** and **ALE** or **coc-ocaml**:

```vim
" In .vimrc
Plug 'ocaml/merlin'
Plug 'dense-analysis/ale'
```

---

## Building T

### Dune Build System

T uses [Dune](https://dune.build/) for building.

**Key Commands**:
```bash
# Build everything
dune build

# Build specific target
dune build src/repl.exe

# Clean build artifacts
dune clean

# Watch mode (rebuild on file changes)
dune build --watch
```

### Build Artifacts

Compiled outputs are in `_build/default/`:
- `src/repl.exe` — REPL executable
- `src/*.cmo`, `src/*.cmi` — Compiled modules
- `tests/*.exe` — Test executables

### Build Configuration

**`dune-project`**: Project metadata
```sexp
(lang dune 3.0)
(name t_lang)
(using menhir 2.1)
```

**`src/dune`**: Build rules for source
```sexp
(executable
 (name repl)
 (libraries arrow-glib))

(menhir
 (modules parser))

(ocamllex lexer)
```

### Dependencies

Managed by Nix (in `flake.nix`):
- **OCaml** 4.14+
- **Dune** 3.0+
- **Menhir** (parser generator)
- **Arrow GLib** (Arrow bindings)
- **GLib** (C library)

Update dependencies:
```bash
nix flake update
nix develop
```

---

## Testing

### Test Structure

```
tests/
├── unit/              # OCaml unit tests
│   ├── test_mean.ml
│   ├── test_filter.ml
│   └── dune
├── golden/            # T vs R golden tests
│   ├── mean.t
│   ├── mean.R
│   └── run_golden.sh
└── examples/          # End-to-end examples
    ├── pipeline_example.t
    └── dune
```

### Running Tests

**All tests**:
```bash
dune runtest
```

**Specific test file**:
```bash
dune runtest tests/unit/test_mean.ml
```

**Verbose output**:
```bash
dune runtest --verbose
```

**Watch mode** (re-run on changes):
```bash
dune runtest --watch
```

### Writing Unit Tests

**`tests/unit/test_example.ml`**:
```ocaml
open Ast
open Eval

let test_addition () =
  let env = Environment.create () in
  let expr = BinOp (Add, Int 2, Int 3) in
  let result = eval env expr in
  assert (result = VInt 5)

let test_mean_basic () =
  let values = [VInt 1; VInt 2; VInt 3] in
  let result = Stats.mean values false in
  assert (result = VFloat 2.0)

let tests = [
  ("addition", test_addition);
  ("mean_basic", test_mean_basic);
]

let () =
  List.iter (fun (name, test) ->
    try
      test ();
      Printf.printf "✓ %s\n" name
    with e ->
      Printf.printf "✗ %s: %s\n" name (Printexc.to_string e)
  ) tests
```

**`tests/unit/dune`**:
```sexp
(test
 (name test_example)
 (libraries t_lang))
```

### Golden Tests

Compare T output against R:

**T program** (`tests/golden/mean.t`):
```t
print(mean([1, 2, 3, 4, 5]))
```

**R script** (`tests/golden/mean.R`):
```r
cat(mean(c(1, 2, 3, 4, 5)), "\n")
```

**Run comparison**:
```bash
# Generate T output
dune exec src/repl.exe < tests/golden/mean.t > /tmp/t_output.txt

# Generate R output
Rscript tests/golden/mean.R > /tmp/r_output.txt

# Compare
diff /tmp/t_output.txt /tmp/r_output.txt
```

**Automated golden test script** (`tests/golden/run_golden.sh`):
```bash
#!/usr/bin/env bash
set -e

for t_file in tests/golden/*.t; do
  base=$(basename "$t_file" .t)
  r_file="tests/golden/${base}.R"
  
  if [ ! -f "$r_file" ]; then
    echo "⚠ Skipping $base (no R script)"
    continue
  fi
  
  dune exec src/repl.exe < "$t_file" > /tmp/t_${base}.txt
  Rscript "$r_file" > /tmp/r_${base}.txt
  
  if diff /tmp/t_${base}.txt /tmp/r_${base}.txt > /dev/null; then
    echo "✓ $base"
  else
    echo "✗ $base (output differs)"
    diff /tmp/t_${base}.txt /tmp/r_${base}.txt
  fi
done
```

---

## Debugging

### REPL Debugging

**Interactive exploration**:
```bash
dune exec src/repl.exe
```

```t
> x = 42
42
> type(x)
"Int"
> x + 10
52
```

**Load script into REPL**:
```bash
cat examples/analysis.t | dune exec src/repl.exe
```

### OCaml Debugger

**Compile with debug symbols**:
```bash
dune build --profile dev
```

**Run with ocamldebug**:
```bash
ocamldebug _build/default/src/repl.exe
```

**Debug commands**:
```
(ocd) break Eval.eval
(ocd) run
(ocd) step
(ocd) print env
(ocd) backtrace
```

### Print Debugging

**In OCaml code**:
```ocaml
let eval env expr =
  Printf.eprintf "DEBUG: evaluating %s\n" (show_expr expr);
  match expr with
  | Int n ->
      Printf.eprintf "DEBUG: int value %d\n" n;
      VInt n
  | _ -> (* ... *)
```

**In T code**:
```t
x = 10
print("DEBUG: x = " + str_string(x))
result = x * 2
print("DEBUG: result = " + str_string(result))
```

### Trace Execution

**Enable tracing** (modify `eval.ml`):
```ocaml
let trace = ref false

let eval env expr =
  if !trace then
    Printf.eprintf "TRACE: %s\n" (show_expr expr);
  (* ... *)
```

**Run with trace**:
```bash
TRACE=1 dune exec src/repl.exe
```

### Error Diagnosis

**Type errors**:
```t
> 1 + "hello"
Error(TypeError: Cannot add Int and String)
```

Check:
- Value types (use `type()`)
- Function signatures
- Conversion functions available

**Name errors**:
```t
> undefined_var
Error(NameError: 'undefined_var' is not defined)
```

Check:
- Variable spelling
- Scope (is it in current environment?)
- Package loaded correctly

**Arrow FFI errors**:
```
Error: Undefined symbol: caml_arrow_read_csv
```

Check:
- You're in Nix shell (`nix develop`)
- Arrow GLib is available: `pkg-config --modversion arrow-glib`
- FFI stubs compiled correctly

---

## Development Workflow

### Typical Development Cycle

1. **Write code** (OCaml or T)
2. **Build**:
   ```bash
   dune build
   ```
3. **Test** (unit + manual):
   ```bash
   dune runtest
   dune exec src/repl.exe
   ```
4. **Debug** (if tests fail):
   - Add print statements
   - Use OCaml debugger
   - Inspect intermediate values
5. **Commit**:
   ```bash
   git add .
   git commit -m "feat: add feature"
   ```
6. **Push and open PR**

### Watch Mode (Fast Iteration)

**Terminal 1** (build on save):
```bash
dune build --watch
```

**Terminal 2** (REPL for testing):
```bash
dune exec src/repl.exe
```

Edit code → save → `dune build` auto-runs → restart REPL → test.

### Working on Standard Library

**Add new function** (`src/packages/stats/median.ml`):
```ocaml
let median values na_rm =
  Stats.quantile values 0.5 na_rm
```

**Register in loader** (if not auto-discovered):
Edit `src/packages/stats/loader.ml` or equivalent.

**Test**:
```bash
dune build
dune exec src/repl.exe
```

```t
> median([1, 2, 3, 4, 5])
3.0
```

**Add unit test** (`tests/unit/test_median.ml`):
```ocaml
let test_median () =
  let result = Stats.median [VInt 1; VInt 2; VInt 3] false in
  assert (result = VFloat 2.0)
```

---

## Performance Profiling

### Timing Execution

**In T**:
```t
start = time()  -- If time() function exists
-- ... computation ...
end = time()
print("Elapsed: " + str_string(end - start))
```

**In OCaml**:
```ocaml
let start_time = Unix.gettimeofday () in
let result = expensive_function () in
let end_time = Unix.gettimeofday () in
Printf.printf "Time: %.3f s\n" (end_time -. start_time);
result
```

### OCaml Profiling

**Compile with profiling**:
```bash
dune build --profile release
```

**Run with `perf` (Linux)**:
```bash
perf record dune exec src/repl.exe < benchmark.t
perf report
```

**Run with `gprof`**:
```bash
# Requires special build flags (modify dune config)
ocamlfind ocamlopt -p -o repl.native src/repl.ml
./repl.native < benchmark.t
gprof repl.native gmon.out
```

### Benchmarking

**Benchmarking script** (`scripts/benchmark.sh`):
```bash
#!/usr/bin/env bash
echo "Benchmarking T operations..."

time dune exec src/repl.exe <<EOF
df = read_csv("large_data.csv")
result = df |> filter($age > 30) |> summarize($count = nrow($age))
print(result)
EOF
```

---

## Common Tasks

### Adding a New Data Type

1. **Update AST** (`src/ast.ml`):
   ```ocaml
   type value =
     | (* ... existing types ... *)
     | VMyNewType of my_new_type_data
   ```

2. **Add constructors and accessors**:
   ```ocaml
   let make_my_type data = VMyNewType data
   ```

3. **Update evaluator** (`src/eval.ml`):
   ```ocaml
   match expr with
   | MyNewTypeExpr data -> VMyNewType (construct data)
   ```

4. **Add pretty-printer**:
   ```ocaml
   let string_of_value = function
     | VMyNewType data -> "MyNewType(...)"
   ```

### Adding a New Operator

1. **Update lexer** (`src/lexer.mll`):
   ```ocaml
   | "@@" { DOUBLE_AT }
   ```

2. **Update parser** (`src/parser.mly`):
   ```ocaml
   %token DOUBLE_AT
   
   expr:
     | expr DOUBLE_AT expr { BinOp (MyOp, $1, $3) }
   ```

3. **Update evaluator** (`src/eval.ml`):
   ```ocaml
   let eval_binop op left right =
     match op with
     | MyOp -> (* implementation *)
   ```

### Adding a New Package

1. **Create directory**:
   ```bash
   mkdir src/packages/mypackage
   ```

2. **Add functions** (one per file):
   ```bash
   # src/packages/mypackage/my_func.ml
   let my_func arg1 arg2 =
     (* implementation *)
   ```

3. **Create loader** (`src/packages/mypackage/loader.ml`):
   ```ocaml
   let load env =
     Environment.add env "my_func" (VNativeFunction my_func)
   ```

4. **Register in main loader** (if needed)

5. **Update documentation**:
   - `docs/api-reference.md`
   - Add examples

### Updating Parser Grammar

1. **Edit** `src/parser.mly`
2. **Rebuild**:
   ```bash
   dune build
   ```
3. **Check for conflicts**:
   ```
   Warning: 2 shift/reduce conflicts
   ```
   
   Fix by:
   - Adjusting precedence (`%left`, `%right`, `%nonassoc`)
   - Refactoring grammar rules
   - Making syntax unambiguous

4. **Test** with examples covering new syntax

### Arrow FFI Development

1. **Write C stub** (`src/arrow/arrow_stubs.c`):
   ```c
   CAMLprim value caml_my_arrow_function(value v_arg) {
     // ... Arrow C GLib calls ...
     return Val_unit;
   }
   ```

2. **Declare in OCaml** (`src/arrow/arrow_ffi.ml`):
   ```ocaml
   external my_arrow_function : arg_type -> return_type = "caml_my_arrow_function"
   ```

3. **Build** (Nix handles linking):
   ```bash
   dune build
   ```

4. **Test**:
   ```t
   > df = read_csv("data.csv")
   > my_new_operation(df)
   ```

---

## Troubleshooting

### Build Fails

**"Command not found: dune"**
- Ensure you're in `nix develop` shell

**"Unbound module"**
- Check `dune` file includes necessary libraries
- Verify module name matches filename

**Menhir conflicts**
- Review parser grammar for ambiguities
- Add `%prec` directives
- Simplify conflicting rules

### Tests Fail

**Unit test assertion fails**
- Add debug prints to see actual vs expected
- Check input data matches test assumptions
- Verify function signature

**Golden test differs**
- Floating-point precision differences (acceptable if small)
- Platform-specific behavior (check on both Linux/macOS)
- R package version mismatch

### Runtime Errors

**Segfault in Arrow FFI**
- Check C stub memory management
- Ensure Arrow objects are not freed prematurely
- Use `valgrind` for memory debugging:
  ```bash
  valgrind --leak-check=full dune exec src/repl.exe
  ```

**"Type error" at runtime**
- Use `type()` to inspect values
- Check function expects correct types
- Verify conversions are explicit

---

## Advanced Topics

### Custom Build Profiles

**`dune-workspace`**:
```sexp
(lang dune 3.0)

(context
 (default
  (name release)
  (flags (:standard -O3))))

(context
 (default
  (name dev)
  (flags (:standard -g))))
```

Build with profile:
```bash
dune build --profile release
dune build --profile dev
```

### Cross-Compilation

Nix supports cross-compilation:

```bash
# For ARM64
nix build .#tlang-arm64

# For macOS from Linux (requires macOS SDK)
nix build .#tlang-darwin
```

### Continuous Integration

See `.github/workflows/` for CI configuration.

**Local CI simulation**:
```bash
# Run same checks as CI
dune build
dune runtest
dune build @fmt --auto-promote  # Format check
```

---

**Next Steps**: [Contributing Guide](contributing.md) | [Architecture](architecture.md)


# FILE: docs/troubleshooting.md

# Troubleshooting Guide

Solutions to common issues when using T.

## Installation Issues

### "command not found: nix"

**Problem**: Nix is not installed or not in PATH.

**Solution**:
```bash
# Install Nix
sh <(curl -L https://nixos.org/nix/install) --daemon

# Restart shell or source profile
source ~/.nix-profile/etc/profile.d/nix.sh
```

**Verify**:
```bash
nix --version
# Should output: nix (Nix) 2.x.x
```

---

### "error: experimental feature 'flakes' is disabled"

**Problem**: Flakes not enabled in Nix configuration.

**Solution**:
```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

**For NixOS users**, add to `/etc/nixos/configuration.nix`:
```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

Then rebuild:
```bash
sudo nixos-rebuild switch
```

---

### "nix develop" hangs or takes very long

**Problem**: Nix is building dependencies from source (first time).

**Solution**: Be patient. First build can take 10-30 minutes.

**Monitor progress**:
```bash
nix develop --show-trace
```

**Speed up future builds**: Nix caches everything in `/nix/store/`.

---

### Build fails with "Could not find arrow-glib"

**Problem**: Inside Nix shell, Arrow should be available. If not, flake may be broken.

**Solution**:
```bash
# Ensure you're in Nix shell
nix develop

# Verify Arrow is available
pkg-config --modversion arrow-glib
# Should output version number (e.g., 10.0.0)
```

**If still failing**: Try updating flake:
```bash
nix flake update
nix develop
```

---

## Build Issues

### "dune: command not found"

**Problem**: Not inside Nix development shell.

**Solution**:
```bash
nix develop
# Now dune should be available
```

---

### "Error: Unbound module Ast"

**Problem**: Modules not compiled or dependency issue.

**Solution**:
```bash
dune clean
dune build
```

**If still failing**: Check `dune` file includes necessary modules.

---

### Menhir shift/reduce conflicts

**Problem**: Parser grammar has ambiguities.

**Example output**:
```
Warning: 2 shift/reduce conflicts
```

**Solution** (for contributors):
- Review `parser.mly` for ambiguous rules
- Add precedence directives (`%left`, `%right`)
- Refactor grammar to remove ambiguity

**For users**: Warnings are okay if parser works correctly. Errors must be fixed.

---

## Runtime Errors

### "Error(NameError: 'x' is not defined)"

**Problem**: Variable or function doesn't exist in current scope.

**Solution**:
1. Check spelling: `prnt` → `print`
2. Check if variable was assigned
3. Check if function is in standard library

**Check available functions**:
```t
> type(print)
"Function"

> type(undefined_func)
Error(NameError: ...)
```

---

### "Error(TypeError: Cannot add Int and String)"

**Problem**: Incompatible types in operation.

**Solution**: Explicit conversion (if available):
```t
-- Bad
"Age: " + 25
-- Error: Cannot add String and Int

-- Workaround: Convert manually or use string concatenation with print
-- Note: Alpha does not have a str_string() conversion function yet
-- Use print for output instead:
print("Age: ")
print(25)
```

---

### "Error(NAError: NA value encountered)"

**Problem**: Operation on NA without explicit handling.

**Solution**: Use `na_rm = true`:
```t
-- Bad
mean([1, 2, NA, 4])

-- Good
mean([1, 2, NA, 4], na_rm = true)
```

---

### "Error(DivisionByZero: Division by zero)"

**Problem**: Dividing by zero.

**Solution**: Guard condition:
```t
-- Bad
x / y

-- Good
if (y == 0) 0.0 else x / y

-- Or use error recovery
(x / y) ?|> \(result) if (is_error(result)) 0.0 else result
```

---

### Segmentation fault (crash)

**Problem**: Usually in Arrow FFI or native code.

**Debugging**:
```bash
# Run with valgrind
valgrind --leak-check=full dune exec src/repl.exe
```

**Workaround**: Avoid Arrow operations, use fallback:
```t
-- May crash with large native DataFrames
df = read_csv("huge.csv")

-- Try smaller data or manual loading
```

**Report**: This is a bug. Please report with minimal reproducible example.

---

## REPL Issues

### REPL doesn't show output

**Problem**: Silent evaluation (no `print`).

**Solution**:
```t
-- Expressions at top-level are printed
> 2 + 3
5

-- But assignments are not
> x = 10
10  -- (value shown but not detailed)

-- Use print for detailed output
> print(x)
10
```

---

### REPL exits on error

**Problem**: Severe error or assertion failure.

**Solution**: Restart REPL. Check what caused the crash and report if reproducible.

---

### REPL hangs on input

**Problem**: Waiting for multiline completion or invalid syntax.

**Solution**:
- Press Ctrl+C to cancel
- Check for unclosed `(`, `{`, `[`
- Ctrl+C now safely interrupts long-running evaluations and returns you to the prompt

---

## Data Loading Issues

### "Error: File not found"

**Problem**: CSV file doesn't exist or wrong path.

**Solution**:
```t
-- Bad (relative to unknown location)
df = read_csv("data.csv")

-- Good (absolute or known relative path)
df = read_csv("/home/user/project/data.csv")

-- Or check file exists first
ls data.csv  # In shell
```

---

### CSV loads with wrong types

**Problem**: Arrow infers types from first rows.

**Solution**: Ensure data is consistent:
- No mixed types in columns
- Missing values represented as empty strings (inferred as NA)
- Numeric columns don't have text

**Workaround**: Preprocess CSV externally or load as strings and convert.

---

### Column names have special characters

**Problem**: Column names like `"Growth%"` not accessible.

**Solution**: Use `clean_colnames = true`:
```t
df = read_csv("data.csv", clean_colnames = true)
-- "Growth%" becomes "growth_percent"
```

---

## Performance Issues

### Operations are very slow

**Problem**: Alpha interpreter is slow, especially for large data.

**Solutions**:
1. **Reduce data size**: Filter early in pipeline
2. **Use native Arrow operations** when available
3. **Chunk processing**: Split large files

**Example**:
```t
-- Slow: Load everything then filter
df = read_csv("huge.csv")
small = df |> filter($year == 2023)

-- Better: Filter during load (if supported) or filter immediately
df = read_csv("huge.csv")
small = df |> filter($year == 2023)  -- Filter early
```

---

### Out of memory

**Problem**: Loading large datasets exhausts RAM.

**Solutions**:
1. **Use streaming** (not yet available)
2. **Process in chunks** (manually split CSV)
3. **Reduce data** before loading:
   ```bash
   # In shell, filter before loading
   grep "2023" huge.csv > subset.csv
   ```

---

## Testing Issues

### Tests fail with floating-point differences

**Problem**: Precision differences across platforms.

**Example**:
```
Expected: 2.333333333
Got:      2.333333334
```

**Solution**: This is acceptable if difference < 1e-6. Update test to allow tolerance.

---

### Golden tests fail (T vs R output differs)

**Possible causes**:
1. Floating-point precision
2. NA handling differences
3. Sorting order for ties

**Solution**: Check if differences are significant or just numerical noise.

---

## Platform-Specific Issues

### macOS: "library not found for -larrow"

**Problem**: Arrow libraries not in library path.

**Solution**: Use Nix shell (this shouldn't happen):
```bash
nix develop
```

If Nix fails, check `flake.nix` for macOS-specific configuration.

---

### WSL2: "Permission denied"

**Problem**: File on Windows mount (`/mnt/c/...`) instead of Linux filesystem.

**Solution**: Clone repository to Linux filesystem:
```bash
# Bad (Windows mount)
cd /mnt/c/Users/username/tlang

# Good (Linux filesystem)
cd ~/tlang
```

---

## Advanced Troubleshooting

### Enable debug logging

**Modify `eval.ml`** (for contributors):
```ocaml
let debug = ref true

let eval env expr =
  if !debug then
    Printf.eprintf "DEBUG: eval %s\n" (show_expr expr);
  (* ... *)
```

---

### Inspect Nix build

**See what Nix is building**:
```bash
nix develop --show-trace
```

**Check Nix store**:
```bash
ls /nix/store/ | grep arrow
ls /nix/store/ | grep ocaml
```

---

### Clean rebuild

**Nuclear option** (removes all build artifacts):
```bash
dune clean
rm -rf _build
nix develop --command dune build
```

---

## Getting More Help

### Before asking for help

1. **Check this guide**
2. **Search [GitHub Issues](https://github.com/b-rodrigues/tlang/issues)**
3. **Try minimal reproducible example**

### When asking for help

Include:
- **Exact error message**
- **Minimal code to reproduce**
- **Your environment**:
  ```bash
  uname -a
  nix --version
  # Inside nix develop:
  ocaml --version
  dune --version
  pkg-config --modversion arrow-glib
  ```

### Where to ask

- **Bugs**: [GitHub Issues](https://github.com/b-rodrigues/tlang/issues)
- **Questions**: [GitHub Discussions](https://github.com/b-rodrigues/tlang/discussions)
- **Documentation improvements**: Pull requests

---

**Still stuck?** Create a [GitHub Issue](https://github.com/b-rodrigues/tlang/issues/new) with details!


# FILE: docs/faq.md

# Frequently Asked Questions (FAQ)

Welcome to the **T Orchestration Engine** FAQ. This guide covers the philosophy, technical architecture, and practical usage of T.

---

## General Questions

### What makes T different?
T isn't just another data analysis language; it's a **reproducibility-first** engine. While R and Python rely on external tools for environment management, T integrates **Nix** at its core. Every workflow is a statically defined directed acyclic graph (DAG) called a **Pipeline**, ensuring that your analysis is as stable as the hardware it runs on.

### Who should use T?
- **Scientific Researchers**: Who need ironclad, auditable proof of how results were derived.
- **Data Engineering Teams**: Looking for a polyglot orchestration layer that passes data between R and Python without serialization overhead.
- **LLM-First Developers**: T's functional, immutable, and pipeline-centric design is optimized for high-fidelity code generation by AI.

### Is T production-ready?
T is currently in **Beta (v0.51.0)**. While it is an experimental project, it is already fully capable of performing end-to-end data processing. You can use T's native **data manipulation verbs** and **Quarto integration** to build reports without ever leaving the language. For more complex statistical modeling or advanced visualization, you can easily pull in R or Python nodes.

---

## The Technical Core

### How does the Polyglot Architecture work?
T uses **Apache Arrow** as its core data exchange format. When you pass a DataFrame between a T node and an **R (`rn()`)**, **Python (`pyn()`)**, or **Shell (`shn()`)** node, T handles the interchange using highly efficient Arrow files. 
- **Hermeticity**: Because T runs every node in a hermetic Nix sandbox, data cannot be shared directly in memory.
- **Serialization**: Dataframes are serialized to Arrow IPC files on disk. This is still significantly faster and more robust than traditional CSV/JSON interchange.
- **Fidelity**: All level metadata for factors and nested list-columns is preserved through the serialization process.
- **Model Interchange**: Machine learning models are passed between languages using **PMML**.

### What is NSE and why the `$` prefix?
T uses **Non-Standard Evaluation (NSE)** to make data manipulation concise. The `$` prefix (e.g., `filter($age > 30)`) identifies column names or variables in the data context, similar to `rlang` in R but built directly into the language syntax for clarity.

### How are missing values (NA) handled?
T takes a strict approach to safety. Unlike other languages where `NA` might propagate silently, T requires explicit handling. 
- Aggregation functions will **throw an error** if they encounter an `NA` unless you pass `na_rm = true`.
- Native types like `na_int()`, `na_float()`, and `na_string()` ensure type-safe missingness.

### Does T have loops or mutable state?
**No.** T is a pure functional language. 
- Instead of `for` or `while` loops, use `map()`, `filter()`, or **recursion**.
- Variables are immutable. This prevents the "spaghetti state" common in long data scripts.

---

## Pipelines & Reproducibility

### Why are Pipelines mandatory?
For non-interactive work, T enforces a `pipeline` block. This ensures that every step of your analysis is declared as a node in a graph. This architecture:
1. Prevents order-of-execution bugs (scripts that only work if run in a specific sequence).
2. Enables **automatic parallelization** of independent nodes.
3. Allows for advanced graph operations like `swap()`, `rewire()`, and `upstream_of()`.

### Do I need to know Nix?
Not for basic work. Running `nix develop` sets up your entire environment. However, T's power comes from Nix—it handles your OCaml, R, Python, and system dependencies in a single, pinned `flake.lock`.

### What operating systems are supported?
- **Linux**: Full **native support** on all modern distributions.
- **macOS**: Full **native support** via the Nix installer (Intel and Apple Silicon).
- **Windows**: Fully supported via **WSL2** (Windows Subsystem for Linux).
- **Docker**: T can build its own Docker images using Nix, making deployment to the cloud seamless.

---

## Data Manipulation & Features

### What libraries are included?
The T standard library includes:
- **`colcraft`**: A powerful suite of verbs (`mutate`, `summarize`, `pivot_longer`) following `tidyverse` semantics.
- **`chrono`**: Precise date and time manipulation with calendar-aware rounding.
- **`factors`**: Native Arrow-backed categorical data handling.

### How do I program with column names?
If you're building a reusable function that takes a column name as an argument, T provides first-class support for **Metaprogramming**:
- Use `enquo(col)` to capture the argument.
- Use `!!` (unquote) to inject it into a verb.
- Use `!!name := value` for dynamic column naming.

Example:
```t
my_avg = \(df, col, name)
  df |> summarize(!!name := mean(!!col))
```

### How do I visualize data?
For simple reports, you can use T's built-in **`colcraft`** verbs to summarize data and output it via **Quarto**. While T does not currently have its own native plotting library, its high-fidelity interop with R and Python makes it trivial to define a specialized node for more complex charts using `ggplot2`, `matplotlib`, or `seaborn`.

### Can T handle large datasets?
**Yes.** T's native Arrow backend allows it to perform `select`, `filter`, and `sort` operations directly on Arrow tables in memory. 
- **Optimized Compute**: T's built-in compute engine handles millions of rows by interacting directly with Arrow memory buffers.
- **Orchestration**: For massive datasets, you can leverage T to orchestrate R's `dtplyr` or Python's `polars` nodes. The results are passed back via Arrow serialization, maintaining high fidelity.

---

## Developer Experience

### Is there an LSP or VS Code support?
Yes! The T Language Server (`t-lsp`) provides:
- **Autocompletion**: For functions, variables, and even **DataFrame column names**.
- **Hover Docs**: View docstrings directly in your editor.
- **Diagnostics**: Real-time syntax and type error reporting.

### What about the REPL?
The T REPL is designed for productivity:
- **Ghost Hints**: Inline suggestions based on your command history.
- **Signal Safety**: Hit `Ctrl+C` to cancel a long-running calculation without crashing the session.
- **Multi-line Detection**: Automatic detection of nested blocks for easy copy-pasting.

### What happens if a node fails or produces a complex object?
T is built with **robustness** in mind. If a node fails (e.g., an R script crashes), T captures the error and presents it as a first-class `VError` value, preventing the whole pipeline engine from crashing.
- **Fail-Safe Loading**: The `read_node()` function will never crash your session. Even if an artifact is missing or corrupted, you get a clean error value you can handle with `?|>`.
- **High-Fidelity Representation**: T works hard to provide native representations of list, dict, and DataFrame objects from other languages.
- **Generic Fallbacks**: If a node produces a complex object that T doesn't natively understand (like a custom private class in Python), it is safely wrapped as a `HostObject`. You can still pass this object as a reference to other nodes of the same language, keeping your polyglot workflow intact.
- **Native Escape Hatch**: If you need to manipulate a complex object that cannot be serialized, you can always read the node's artifact directly using the native interpreter's own libraries (e.g., by calling `read_node()` inside a Python or R script).

### Can I write Literate Programming reports?
Absolutely. T integrates with **Quarto** through a native extension. You can write `.qmd` files where code chunks are written in **pure T**, allowing you to summarize data and generate professional reports without ever needing R or Python. For advanced charting or low-level file processing, you can mix T chunks with R, Python, or **Shell** (using the `shn()` function) in the same document.

---

## Community & Contributing

### How can I help?
T is an open-source project. You can contribute by:
- Porting R/Python utility functions to native T.
- Improving the `t-lsp` implementation.
- Reporting bugs or suggesting features on [GitHub](https://github.com/b-rodrigues/tlang/issues).

### What's next on the roadmap?
The developer (Bruno Rodrigues) works on T based on community interest and experimental whims. High-priority items include **Julia integration** and expanding the native Arrow compute engine.

---

> [!TIP]
> **Need help?** Check out the [Getting Started](getting-started.md) guide or join the [GitHub Discussions](https://github.com/b-rodrigues/tlang/discussions).
