# T Language Reference (Huge - Full Documentation)

This file is a concatenation of the entire T documentation for LLM context.



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
├── AGENTS.md           # Onboarding guide for AI Agents
├── T-LANGUAGE-REFERENCE.md # Tiered language reference for LLMs (git-ignored)
├── src/
│   └── pipeline.t      # Your main analysis script
├── data/               # Place your raw data files here
├── outputs/            # Output directory for results
└── tests/              # Unit tests for your analysis
```

### AI Agent Onboarding

T is designed to be highly compatible with AI-assisted development. When you run `t init`, the tool will prompt you for an **Agent Context Level**:

- **small**: Core syntax and top 20 functions.
- **medium**: (Default) Exhaustive standard library index.
- **full**: Full language manual and detailed examples.
- **huge**: Concatenated documentation of the entire T ecosystem.

This selection generates two files in your project root:
1. **`AGENTS.md`**: A project-specific guide that tells LLMs how to work within your project's architecture.
2. **`T-LANGUAGE-REFERENCE.md`**: A technical reference file for the AI to read.

By providing these files, you ensure that any AI agent you use has immediate access to the exact technical context it needs.

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
├── AGENTS.md           # Onboarding guide for AI Agents
├── T-LANGUAGE-REFERENCE.md # Tiered language reference for LLMs (git-ignored)
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

Fit a linear regression model (OLS). The formula is a `Formula` value such as `mpg ~ wt + hp`.

---

#### `summary(model)` / `fit_stats(model)`

`summary(model)` returns a `Dict` containing a `_tidy_df` DataFrame plus metadata; `fit_stats(model)` returns a `DataFrame` of model-level metrics.

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


# FILE: docs/arrow-current-status-next-steps.md

# Arrow: current status and next steps

This document summarizes the current Apache Arrow-related state of the repository across `docs/`, `src/`, `tests/`, and `spec_files/`.

It is meant to answer four questions:

1. What Arrow-related code and documentation already exist?
2. What is currently implemented vs. still missing?
3. What do the current tests cover?
4. What tests and documentation should be added next?

## Executive summary

The repository already has a substantial Arrow backend:

- a dedicated Arrow implementation under `src/arrow/`,
- a large C FFI layer in `src/ffi/arrow_stubs.c`,
- Arrow IPC read/write builtins (`read_arrow`, `write_arrow`),
- pipeline-level Arrow serialization/deserialization support,
- dedicated Arrow integration and performance tests,
- and multiple planning/hardening documents in `spec_files/`.

The most important caveat is that the repository currently mixes **current-state docs** and **historical planning docs**:

- some newer files reflect the real backend well,
- while some older planning/spec documents still describe Arrow as mostly unimplemented or stubbed.

There is also still an important CSV-path distinction to document clearly:

- `src/arrow/arrow_io.ml` contains a native Arrow CSV reader,
- and the public `read_csv` builtin in `src/packages/dataframe/t_read_csv.ml` now delegates to `Arrow_io.read_csv` when callers use the default CSV options.
- non-default parsing behaviors such as custom separators, header skipping, line skipping, and column-name cleaning still use the OCaml parser path.
- this is now a documented split between the fast native default path and the richer compatibility path, rather than an entirely missing integration.

So Arrow support is real and broad, but not yet fully unified or fully documented from a user point of view.

## What exists today

### Documentation in `docs/`

The existing documentation mentions Arrow in several places, and `docs/arrow-current-status-next-steps.md` now serves as the dedicated Arrow overview/status page.

Relevant files:

- `docs/architecture.md`
  - describes Arrow as the DataFrame backend and mentions zero-copy access and vectorized compute.
- `docs/installation.md`
  - explains that the Nix environment builds Apache Arrow and related dependencies.
- `docs/troubleshooting.md`
  - includes Arrow-specific setup and debugging notes such as `arrow-glib` availability and native-code crash guidance.
- `docs/performance.md`
  - is currently the closest thing to an Arrow backend overview.
  - explains native vs fallback execution paths, zero-copy numeric views, grouping, and performance expectations.

Current documentation strengths:

- readers can tell that Arrow exists and is important,
- installation and troubleshooting mention Arrow dependencies,
- performance docs explain the native/fallback split.

Current documentation gaps:

- the generated reference docs for `read_arrow` / `write_arrow` exist, but there is still no broader user-facing Arrow I/O guide,
- there is still no concise support matrix explaining which Arrow types are fully supported, partially supported, or still fallback-only,
- the status page exists, but the rest of the docs do not yet surface it as the central Arrow landing page,
- there is still no short docs-facing summary of what the Arrow tests cover.

### Source code in `src/`

#### Core backend

The dedicated Arrow implementation lives in:

- `src/arrow/arrow_table.ml`
- `src/arrow/arrow_compute.ml`
- `src/arrow/arrow_io.ml`
- `src/arrow/arrow_ffi.ml`
- `src/arrow/arrow_bridge.ml`
- `src/arrow/arrow_column.ml`
- `src/arrow/arrow_owl_bridge.ml`
- `src/ffi/arrow_stubs.c`

Taken together, these files provide:

- Arrow-backed table representation with optional native handle,
- pure-OCaml fallback tables,
- schema/type mapping,
- native materialization when supported,
- Arrow compute wrappers for projection, filtering, sorting, scalar arithmetic, math, aggregation, comparisons, and grouping,
- Arrow IPC read/write,
- native list-column and dictionary-column support,
- date support,
- NA-only native materialization support,
- zero-copy numeric column views via Bigarray,
- conversion between Arrow storage and T runtime values,
- bridge utilities for statistical work via `Arrow_owl_bridge`.

#### User-facing and integration entry points

Arrow also shows up outside `src/arrow/`:

- `src/packages/dataframe/t_read_arrow.ml`
  - exposes Arrow IPC reading to T as `read_arrow`.
- `src/packages/dataframe/t_write_arrow.ml`
  - exposes Arrow IPC writing to T as `write_arrow`.
- `src/packages/dataframe/t_dataframe.ml`
  - `dataframe`, `pull`, and `to_array` all interact with Arrow-backed tables and Arrow-derived column types.
- `src/packages/dataframe/t_read_csv.ml`
  - creates Arrow-backed DataFrames and uses `Arrow_io.read_csv` for the default public CSV path, while routing non-default parsing options through the OCaml parser plus `Arrow_bridge`.
- `src/pipeline/builder_read_node.ml` and `src/packages/pipeline/read_node.ml`
  - use Arrow IPC reading in pipeline flows.
- `src/pipeline/nix_emit_node.ml`
  - emits Arrow helpers for R/Python pipeline nodes and wires Arrow serializer/deserializer behavior into generated node code.
- `src/dune`
  - builds and links the Arrow C stubs through `arrow-glib`.

## What is currently implemented

### Clearly implemented today

Based on the code currently in the repository, the following are present:

- Arrow-backed tables with GC-managed native handles
- native/fallback dual-path execution
- schema extraction and column access
- project/select
- filter
- sort/arrange
- add/replace column behavior
- scalar arithmetic (`add`, `subtract`, `multiply`, `divide`)
- unary math (`sqrt`, `abs`, `log`, `exp`, `pow`)
- column aggregations (`sum`, `mean`, `min`, `max`)
- scalar comparisons
- group-by plus group aggregations (`sum`, `mean`, `count`)
- Arrow IPC read/write
- dictionary/factor columns
- list columns with nested DataFrame reconstruction
- date columns
- NA-only columns
- zero-copy views for native numeric columns
- Arrow-to-Owl bridge for numeric/statistical workflows
- serialization hardening for native-backed DataFrames crossing process boundaries
- runtime disable switch via `TLANG_DISABLE_ARROW`

### Implemented, but not consistently surfaced

These features exist in the backend, but are not yet cleanly represented in user-facing docs or entry points:

- Arrow IPC support is implemented, but under-documented.
- Pipeline Arrow interop exists, but most of the narrative lives in `spec_files/` and tests rather than in `docs/`.
- Native Arrow CSV reading exists in `src/arrow/arrow_io.ml`, and the public `read_csv()` builtin uses it for the default CSV path.
- `docs/performance.md` still describes dictionary/factor, list, and date columns as unsupported for native rebuild even though the code now includes native dictionary, list, and date materialization paths.

### Partially implemented or still limited

The code also shows some areas that are either incomplete or intentionally constrained:

- **Datetime native materialization**
  - `Arrow_table.DatetimeColumn` exists and `Arrow_io.build_column` can parse timestamps,
  - but `Arrow_table.is_arrow_table_new_supported` still rejects `DatetimeColumn`,
  - and the Arrow type-tag mapping does not currently expose a dedicated timestamp tag in the same way it does for date/dictionary/list.
- **List columns**
  - native support exists, but only for list-of-struct shapes whose sub-fields are primitive supported types and whose nested tables share a schema.
- **CSV path consistency**
  - there are effectively two Arrow-related CSV stories:
    - backend-native `Arrow_io.read_csv`,
    - user-facing `read_csv` in `t_read_csv.ml`.
  - These should eventually converge.

## What appears to be missing

### Missing or underdeveloped user-facing documentation

- A single Arrow overview/status page in `docs/`
- User docs for `read_arrow` and `write_arrow`
- Documentation for Arrow-backed pipeline interchange as a supported workflow
- Clear support matrix for:
  - primitive columns,
  - date/datetime,
  - dictionary/factor,
  - list/nested columns,
  - NA-only columns,
  - zero-copy views,
  - IPC read/write
- Explicit documentation of the difference between:
  - Arrow backend capabilities,
  - public language entry points,
  - fallback behavior

### Missing or incomplete implementation items

The main implementation gaps that stand out from the current code are:

1. **Public CSV path still has a split implementation**
   - The default `read_csv()` path now uses `Arrow_io.read_csv`, but option-rich parsing still uses the OCaml parser path.
   - This is now mostly a documentation and consistency question rather than a missing integration.

2. **Native datetime round-trip/materialization**
   - Date is present; datetime/timestamp support is only partial.

3. **Broader native materialization coverage**
   - list-column support is constrained to compatible nested schemas.

4. **Documentation/source alignment**
   - some docs still describe features as missing even though they are implemented.

5. **Historical spec cleanup**
   - older planning docs still describe the backend as “not started” or “stubbed,” which is useful historically but confusing if read as current status.

## What the current tests cover

### Dedicated Arrow tests

The main dedicated Arrow coverage is in:

- `tests/arrow/test_arrow_integration.ml`
- `tests/arrow/test_arrow_performance.ml`
- `tests/arrow/test_owl_bridge.ml`
- `tests/test_arrow_native_runner.ml`
- `tests/test_arrow_helpers.ml`

`tests/dune` wires the Arrow tests into both the regular test runner and a dedicated Arrow-native runner.

#### `tests/arrow/test_arrow_integration.ml`

This file covers a lot of backend behavior already:

- FFI availability flag
- pure-OCaml table creation and schema access
- column lookup and basic table operations
- bridge conversions (`column_to_values`, `values_to_column`, `row_to_dict`)
- T-level CSV-driven DataFrame operations (`read_csv`, `select`, `filter`, `mutate`, `arrange`, pipelines)
- native-path visibility through `explain(...).native_path_active`
- compute module coverage for:
  - project
  - filter
  - sort
  - scalar arithmetic
  - grouping and grouped aggregation
- zero-copy view behavior
- temporal parsing helpers for date/timestamp string parsing
- dictionary/factor support, including ordered-factor round-trips
- list-column support, including:
  - native materialization
  - NA entries
  - empty/all-NA fallback behavior
  - sparse NA-heavy cases
  - repeated lifecycle queries
  - GC stress loops
  - T-level `nest`, `unnest`, and `slice` regressions

This is already a strong regression suite for the Arrow backend internals.

#### `tests/arrow/test_arrow_performance.ml`

This file is less about benchmarking precision and more about smoke-testing broader behavior at realistic sizes:

- native CSV read smoke path via `Arrow_io.read_csv`
- zero-copy numeric views on native-backed tables
- column-view helpers
- vectorized math functions
- column aggregations
- comparison operations
- larger-table operations at 10k / 100k / 1M rows
- group-by and grouped aggregation on larger data
- large-data math/comparison smoke tests

So this file already covers scale-oriented sanity checks, not just micro-features.

#### `tests/arrow/test_owl_bridge.ml`

This file covers Arrow-to-statistics integration:

- numeric extraction through the bridge
- `lm()` behavior through the bridge
- `cor()` behavior through the bridge
- error handling for missing columns, bad input types, and NA cases

### Pipeline-level Arrow coverage

Arrow also appears in pipeline tests such as:

- `tests/pipeline/test_arrow_interop.t`
- `tests/pipeline/test_factor_roundtrip.t`
- several GLM / lab / PMML pipeline tests that use `serializer = "arrow"` and/or `deserializer = "arrow"`

These tests show that Arrow is not just a local DataFrame backend. It is also being used as the interchange format between T, R, and Python pipeline nodes.

That is important coverage, even though it is spread across the pipeline suite rather than grouped under `tests/arrow/`.

## What tests should be added next

The current tests are strong, but there are still some obvious gaps.

### Highest-priority tests to add

1. **Broaden Arrow IPC round-trip coverage**
   - Dedicated tests already exist for:
     - `Arrow_io.read_ipc`
     - `Arrow_io.write_ipc`
     - `read_arrow`
     - `write_arrow`
   - Round-trips now cover:
     - primitive tables,
     - dictionary/factor tables,
     - list-column tables where supported,
     - NA-only columns.
   - The remaining useful additions are edge cases such as empty structures and future datetime/timestamp coverage.

2. **Public `read_csv()` path tests that distinguish implementation path**
   - The repository currently tests `read_csv()` behavior, but not the architectural distinction between:
     - builtin `read_csv`,
     - backend-native `Arrow_io.read_csv`.
   - We should add tests that make this difference explicit so future refactors do not silently change backend behavior.

3. **Datetime/timestamp support tests**
   - The code currently tests timestamp parsing helpers, but not a full native round-trip story.
   - Add tests for:
     - datetime columns in DataFrames,
     - expected fallback behavior where native rebuild is unsupported,
     - eventual native round-trip once implemented.

4. **IPC/pipeline regression tests for Arrow serializer helpers**
   - There is already meaningful Arrow serializer/deserializer coverage through `tests/pipeline/test_arrow_interop.t` and other pipeline fixtures.
   - A smaller focused `read_node`/serializer boundary test would still be useful so this behavior is not covered only through broader end-to-end scenarios.

### Good next regression additions

5. **Deeply nested list-column tests**
   - The regression spec already calls out deeper list nesting as a useful target.

6. **List-column containing dictionary/factor sub-fields**
   - This is called out in `spec_files/arrow-regression-testing.md` and would exercise a high-risk interaction.

7. **Multi-chunk Arrow array tests**
   - The FFI explicitly combines chunked arrays, but there is no obvious dedicated regression test for multi-chunk column recombination.

8. **NA-only and empty-structure IPC tests**
   - Current tests cover some fallback behavior, but dedicated IPC round-trip checks would be valuable.

9. **Tests that assert docs-visible behavior**
   - For example, tests or snapshots around `explain(df).storage_backend` and `native_path_active` for representative schemas.

## What documentation should be added or updated next

### Add

1. **A dedicated user-facing Arrow I/O page**
   - `docs/reference/read_arrow.md` and `docs/reference/write_arrow.md` already exist.
   - The remaining gap is a broader narrative page that explains Arrow IPC workflows and where they are used.

2. **A support matrix page or section**
   - per type / operation:
     - supported natively,
     - supported with fallback,
     - not yet implemented.

3. **Better docs surfacing for the current status page**
   - link this page from the main Arrow-related docs so readers can find the implementation-status overview without searching `spec_files/` or `docs/`.

### Recently closed gap

- **NA-only native rebuild/materialization**
  - `NAColumn` can now be materialized back into a native Arrow table, which means NA-only DataFrames can remain on the native Arrow path and participate in Arrow IPC round-trips.

### Update

1. **`docs/performance.md`**
   - update rebuild/fallback examples so they match the current code.
   - In particular, dictionary, list, and date support should be described more accurately.

2. **`docs/architecture.md`**
   - add a clearer summary of Arrow IPC and pipeline interop, not just the table backend.

3. **Docs for `read_csv()`**
   - document the current reality:
     - what the user-facing builtin does today,
     - how it relates to `Arrow_io.read_csv`,
     - whether the native CSV reader is backend-only or intended to become the default path.

4. **Potentially annotate older spec files as historical**
   - especially files that still say Arrow is “not started” or “stubbed.”

## Recommended next steps

If the goal is to make Arrow status clear and reduce confusion, the best next steps are:

1. **Unify or explicitly document the CSV story**
   - either switch the public `read_csv()` builtin to `Arrow_io.read_csv`,
   - or document why the current split exists.

2. **Add dedicated Arrow IPC round-trip tests**
   - this is the clearest missing test area.

3. **Document the current support matrix**
   - especially for dictionary, list, date, datetime, and NA-only columns.

4. **Refresh stale docs/spec language**
   - so readers can distinguish:
     - historical plans,
     - current implementation,
     - future work.

5. **Add focused pipeline Arrow IPC regression tests**
   - especially around `read_node` and serializer/deserializer boundaries.

## Bottom line

Arrow in this repository is no longer a speculative or early-stub feature. It is a real backend with:

- native tables,
- native compute hooks,
- Arrow IPC,
- pipeline interchange,
- zero-copy numeric access,
- factor/list/date support,
- and meaningful regression coverage.

What is missing is not “Arrow support” in general. What is missing is:

- clearer status documentation,
- a more unified public entry-point story,
- fuller IPC-focused tests,
- and cleanup of outdated planning language that no longer reflects the current codebase.


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


# FILE: docs/changelog.md

# Changelog

## [Unreleased]

The focus of this release was to improve language ergonomics for data guardrails and increase test coverage across all packages.

**Status**: Beta  

### Language Ergonomics
- **Default Value Support in `get()`**: Enhanced the `get()` primitive to support default value fallbacks. It now handles:
    - `get(potential_error_or_na, default)`: Returns the default if the first argument is an error or NA.
    - `get(target, selector, default)`: Returns the default if the retrieval from the target fails.
    - This enables concise and safe data guardrails, such as `get(s.min_age, 0) >= 0`, which gracefully handles missing columns or empty summaries.

### Quality & Test Coverage
- **Expanded Stats Package Coverage**:
    - Enhanced ONNX test coverage by adding a Decision Tree Classifier test suite.
    - Fixed `generate_onnx.py` compatibility with scikit-learn 1.6+ and ensured numeric output parity for classification models.
    - Stabilized PMML prediction golden tests by tightening the random-forest regression tolerance to `1e-2` to preserve cross-runtime stability without masking meaningful regressions.
    - Added comprehensive golden tests for 15+ specialized statistical functions, probability distributions, and transformations.
    - **Specialized Metrics**: Verified `cv`, `fivenum`, `trimmed_mean`, `mad`, `iqr`, `range`, `var`, and `cov` against R baselines.
    - **Advanced Moments**: Added coverage for `skewness` and `kurtosis` (excess kurtosis) using population-moment calculations.
    - **Probabilistic Distributions**: Added golden tests for `pnorm` (standard normal approximation), `pt`, `pf`, and `pchisq` CDFs.
    - **Statistical Operations**: Verified `winsorize`, `huber_loss`, `normalize`, and Pearson `cor` against R reference values.
    - **Data Transformations**: Added a golden test for `standardize` and `scale` using `iris$Sepal.Length`.
    - **Model Accessors**: Added regression tests for `coef`, `conf_int`, `sigma`, `nobs`, and `df_residual` for linear models.
- **Cross-Platform Stability**:
    - **Darwin Portability**: Fixed non-portable shell behavior and path symlink inconsistencies in `builder_utils.ml` and `test_misc_coverage.ml`. Switched to `Unix.realpath` for canonical path resolution on macOS (handling `/var` vs `/private/var`) and ensured GNU utilities are explicitly used via Nix environment wrappers.
- **Critical Fixes & Statistics Parity**:
    - **ONNX Input Alignment**: Synchronized the native ONNX evaluator with regenerated model fixtures, updating expected input metadata from `X` to `float_input` to match `scikit-learn` 1.6+ exports.
    - **Metadata Parity**: Injected `model_type` and `mining_function` metadata into `lm` and PMML-loaded model objects. This ensures that `fit_stats()` returns complete, R-compatible diagnostic tables without `NA` placeholders for model categories.
    - **Enhanced `anova`**: Updated the `anova` builtin to support model labels (e.g., `anova(m1 = m1, m2 = m2)`). The labels are now preserved in the resulting DataFrame, matching R's behavior in model comparison tables.
    - **Quantile Accuracy**: Fixed a critical bug in the C-based quantile implementations (`normal_quantile`, `t_quantile`) where tail approximations were incorrect, leading to broken confidence intervals. Implemented high-precision Acklam's algorithm for normal quantiles and accurate Cornish-Fisher expansion for $t$ quantiles.
    - **Test Runner Stability**: Suppressed noisy `onnxruntime` CPU vendor warnings in the golden test suite and standardized the "✓" success indicator across all statistical test scripts.
    - **PMML Prediction Consistency**: Resolved floating-point discrepancies in PMML random forest regression predictions by implementing standard tolerances in the golden test suite, ensuring cross-environment test reliability.
- **Improved Base Package Coverage**:
    - Significantly increased test coverage for `base` package builtins, specifically targeting error handling, NA container logic, and serialization.
    - **NA Mapping**: Verified `is_na` vectorization across Vectors and named Lists.
    - **Serialization Robustness**: Added comprehensive error-path testing for `serialize`, `deserialize`, `t_write_json`, and `t_read_json`, including type-mismatch and file-system failure scenarios.
- **Improved Core Package Coverage**:
    - Expanded test coverage for `core` package builtins, including `args`, `help`, `apropos`, and `write_text`.
    - **Introspection**: Added tests for the `args()` builtin on both builtins and lambdas, ensuring correct parameter name and type extraction.
    - **Core Unit Tests**: Expanded coverage for `identical` (deep equality), `sum` (edge cases), `seq` (auto-descending ranges), and `head`/`tail` (slicing boundaries).
    - **Coverage Boost**: Significantly increased coverage for `ifelse`, `casewhen`, and `identical` (t_boolean.ml), `get` with all lens types (t_get.ml), and all specialized rendering paths in `pretty_print.ml`.
    - **Coverage Integration**: Added the new colcraft coverage tests to the test runner so these scenarios are exercised in regular test execution.
    - **Colcraft Coverage**: Expanded testing for `fill`, `replace_na`, `complete`, `relocate`, `count`, `slice`, `unnest`, `separate`, and `uncount`. Verified `downup` direction logic and regex error handling.
    - **Pretty Printing**: Verified nested collection and visual metadata (Altair) rendering in `pretty_print`.
    - **Help System**: Added regression coverage for invalid input types and missing-documentation cases in `help()` and `apropos()`.
- **Improved Lens Package Coverage**:
    - Significantly increased test coverage for the `lens` package, focusing on custom lenses, pipeline orchestration, and recursive mapping.
    - **Custom Lenses**: Added coverage for Dictionary-based lenses with user-defined `get` and `set` functions.
    - **Pipeline Orchestration**: Verified `node_meta_lens` for `serializer` and `deserializer` fields, and `filter_lens` for batch updates to pipeline node values.
    - **Recursive Mapping**: Added tests for `col_lens` and `idx_lens` across nested Lists of Vectors and DataFrames.
    - **Resilience**: Verified error propagation and halt-on-failure behavior in the variadic `modify()` builtin.
- **Enhanced Arity Error Reporting**:
    - Updated the core evaluator to include function names in arity error messages for all builtins (e.g., `Function `length` expects...`).
    - Standardized arity error expectations across the entire test suite (1944/1944 tests passing).

## [0.51.4] - 2026-04-30

**Status**: Beta  

### AI Agent Onboarding & Context Tiering
- **Tiered Language Reference**:
    - Introduced a tiered system for language reference files (`small`, `medium`, `full`, `huge`).
    - **`huge` reference generation**: Implemented a recursive build process in `docs/build.sh` that concatenates the entire documentation ecosystem into a single, comprehensive reference for high-context agents.
- **Interactive Scaffolding**:
    - Updated `t init` to be fully interactive. The CLI now prompts for the **AI Agent Context Level** during project or package initialization.
    - **`AGENTS.md`**: Automatically generates project-specific onboarding guides for LLMs based on the workspace type.
    - **Automated Deployment**: The chosen reference level is deployed as `T-LANGUAGE-REFERENCE.md` in the project root and automatically added to `.gitignore`.
- **LLM-First Documentation**:
    - Updated the `README`, `Getting Started`, and `LLM Collaboration` guides to emphasize T's unique support for agentic development.

### Language Ergonomics & Auto-Quoting
- **Auto-Quoted Parameters (`$param`)**: 
    - Introduced `$param` syntax in lambda and `function()` parameter lists.
    - Parameters prefixed with `$` automatically capture bare names (like column names) as **Symbols** rather than evaluating them.
    - Simplified the creation of data-wrangling wrappers, removing the need for `enquo()` in simple forwarding cases.
- **Unified `get()` and New `sym()` Builtin**:
    - Added the `sym()` core builtin for programmatic symbol creation.
    - Unified the `get()` dispatcher across `core` and `lens` packages, ensuring a single, stable interface for variable lookup, collection indexing, and lens-based retrieval.
    - **Regression Safety**: Added regression tests to ensure core primitives remain stable when the `lens` package is loaded.

### Structural Integrity & Terminal Error Handling
- **Introduced `StructuralError` Category**:
    - Added `StructuralError` as a new terminal diagnostic code for fundamental pipeline orchestration failures.
    - **DAG Validation**: Dependency cycles, self-referential nodes, and missing sibling node references are now classified as `StructuralError`.
    - **Orchestration Failure**: Materialization errors in `populate_pipeline` (e.g., missing dependencies in `tproject.toml`, missing Nix build tools, or stalled artifact directories) now emit `StructuralError`.
- **Terminal Evaluation Policy**:
    - The core evaluator now treats `StructuralError` as a **terminal event** that bypasses "Resilient-by-Default" (`resilient=true`) settings.
    - This ensures that fundamental infrastructure or topology breaks stop script execution immediately, preventing confusing downstream "cascading gibberish" errors while maintaining resilience for standard data-computation errors (like `1 / 0`).
- **Environment-Aware Failures**:
    - Pipeline dependency checks now respect the `TLANG_AUTO_ADD_PIPELINE_DEPS` environment variable.
    - If auto-injection is disabled or impossible (non-interactive sessions), the system raises a fatal `StructuralError` instead of implicitly continuing into a broken Nix state.

### Pipeline Infrastructure & Lens Orchestration
- **Resolution Stabilization**:
    - Implemented robust lazy resolution for cross-pipeline dependencies and out-of-order pipeline nodes.
    - Fixed a regression where pipeline nodes were returning `unbuilt` states instead of resolved values in complex dependency graphs.
- **Improved Failure Visibility**:
    - Introduced structured `MissingArtifactError` in the lens system to provide precise feedback on unbuilt dependencies during lazy evaluation.
    - Clarified the error contract for `get()` when targeting plotting nodes, ensuring metadata dictionaries are returned predictably.

### First-Class Visual Metadata & Plot Inspection
- **Automated Plot Metadata Capture**: 
    - Implemented infrastructure to automatically extract and persist metadata from visual objects in polyglot pipelines.
    - **R Support**: Capture titles, labels (x, y, color, etc.), mappings, and layers from `ggplot2` objects.
    - **Python Support**: Full metadata extraction and inspection support for `matplotlib` figures, `plotnine` (ggplot-style), `seaborn` grids, `plotly` figures, and `altair` charts.
- **Enhanced `show_plot()` Builtin**:
    - Introduced `show_plot()` to render and open pipeline plot artifacts locally.
    - Supports automatic rendering of R (`ggplot2`) and Python (Matplotlib, Seaborn, Plotly, Altair, Plotnine) plots within the Nix sandbox.
    - Implemented headless rendering for interactive libraries: Plotly (via `kaleido`) and Altair (via `vl-convert`).
    - **Dependency Automation**: `tlang` now automatically suggests or injects `cloudpickle` when plotting libraries are detected in Python nodes to ensure reliable serialization of complex objects containing lambdas.
- **Transparent `read_node()` for Plots**:
    - `read_node()` now recognizes nodes of class `ggplot`, `matplotlib`, `plotnine`, `seaborn`, `plotly`, or `altair`.
    - Instead of returning an opaque binary artifact, it returns a structured JSON-backed dictionary of the plot's metadata, enabling programmatic verification of visualizations in T scripts.

### Serializable Lens Architecture
- **Refactored Lens Implementation**:
    - Replaced functional closure-based lenses with a structured `VLens` sum type.
    - **Nix-Isolated Persistence**: Lenses can now be serialized to disk and passed between separate Nix-build pipeline nodes without losing their state or functionality.
    - **Unified `get()` Integration**: The `get()` builtin now natively supports `VLens` for data focus, providing a single, consistent interface for variable lookup, indexing, and lens-based retrieval.

### Core Evaluator, Emitter & Documentation Refinements
- **Improved Docstring Coverage**: Added full T-style documentation (descriptions, parameters, examples) for `get()`, `sym()`, and related primitives.
- **Integrated Documentation Tooling**: Verified `t_doc("parse")` and `t_doc("generate")` workflows for extracting and publishing reference pages for new core functions.
- **Auto-Quoting Documentation**: Updated `docs/language_overview.md` and `docs/quotation.md` with comprehensive examples of the new `$param` auto-quoting feature.

### Editor Support & Tree-sitter
- **Official Tree-sitter Grammar**:
    - Introduced a formal Tree-sitter grammar for T in `editors/tree-sitter-t`.
    - Supports robust syntax highlighting, local scope resolution, and language injections.
    - **Polyglot Injections**: Automatically injects R, Python, and Bash syntax highlighting into `<{ }>` blocks when used inside `rn()`, `pyn()`, or `shn()` calls (supporting both named and positional arguments).
    - **Expanded Highlighting**: Highlighting coverage expanded to include ~140+ standard library functions across all core packages.
    - **Editor Integration**: Added documentation and configuration examples for Neovim, Emacs 29+, VS Code, and other Tree-sitter compatible editors.
### Core Evaluator & Emitter Refinements
- **Quarto Wrapper Ergonomics**: Added `qn()` as a first-class convenience wrapper around `node()` with `runtime = Quarto`, matching the existing `rn()` and `pyn()` helpers for R and Python nodes.
- **Improved Pretty Printing**: Updated the core pretty printer to handle complex nested dictionaries and diagnostics summaries more gracefully.
- **Nix Emitter Stability**: Significant updates to `nix_emit_node.ml` to support the new visualization injection logic and improve script-based node robustness.
- **Test Infrastructure**: Added the `get_sym_demo_t` comprehensive demo project with dedicated CI validation and automated assertions.

### Bug Fixes & Refinements
- **Visualization Stability**: Fixed a critical `Printf.sprintf` type error in the Python plot rendering logic that prevented pipeline builds for Python-based visualizations.
- **Improved REPL interaction**: Explicitly flush stdout/stderr around `show_plot` calls so the rendered path is reported cleanly before local viewer launch.
- **Helper Consistency**: Standardized lens helper names and improved internal consistency in `lens.ml`.
- **Pipeline Predicate Scoping**: Fixed a regression where `filter_node(is_na($diagnostics.error))` and `which_nodes(is_na($diagnostics.error))` could evaluate outside the node metadata scope and incorrectly exclude nodes without diagnostics errors.


### Resilient-by-Default Evaluation
- **Global Resilience**: Evaluation now defaults to resilient mode (`resilient=true`). This ensures that scripts and pipelines continue execution upon encountering `VError` values, aligning with the "Errors are Values" philosophy.
- **`--failfast` Flag**: Replaced the `--resilient` CLI flag with `--failfast`. Users can now explicitly opt-in to the usual, common behaviour of short-circuiting upon the first error.
- **`t_make()` & `t_run()` Integration**: Added `failfast` parameter to the main pipeline orchestrator and script runner for granular control.
- **Improved Serialization Restoration**: Fixed a critical bug where `VError` values were deserialized as Dictionaries. The system now correctly restores the native `Error` type across node boundaries, even when using modern JSON interchange.

## [0.51.3] - 2026-04-12

**Status**: Beta  

### Pipeline Infrastructure & Observability
- **First-Class Diagnostics Engine**: 
    - Implemented a comprehensive diagnostics system that captures and classifies "own" vs. "upstream" warnings.
    - Pipeline builds now persist non-terminal warnings and terminal errors as node artifacts.
    - **Soft-Fail Semantics**: Internal node failures no longer halt the entire Nix build; they produce `VError` objects, allowing independent branches to complete.
    - **Diagnostic Suppression**: Introduced `suppress_warnings` combinator to silence high-noise nodes while maintaining background auditability.
    - **Improved Summaries**: Updated build summaries to use plural-safe `node(s)` and `error(s)` formatting, with clear iconographic reporting (`✖`, `✓`, `○`, `?`).
- **Enhanced Interrogation Tools**:
    - **`read_node()` & `read_pipeline()`**: Promoted to first-class tools. They now accept in-memory objects and return structured results with values and diagnostics.
    - **`explain()` function**: Enhanced to surface context, tracebacks, and missingness statistics for pipeline results and errors.
    - **Verbose Logging**: Added `verbose=1` support to pipeline builders, mapping directly to Nix build logs for improved debugging.
- **Architectural Improvements**:
    - **Lazy Evaluation**: Implemented lazy cross-pipeline dependency resolution, allowing expressive and ergonomic pipeline composition.
    - **Resilient Path Resolution**: Fixed repository root discovery for nested builds and Nix sandboxes.
    - **Dependency Traceability**: Automatic injection of `node_name` into all diagnostic records for clear error attribution in complex DAGs.

### Standardized Missingness & "Death to Null"
- **Comprehensive NA Enforcement**:
    - Finalized the T-Lang NA specification for total "No Silent Magic" compliance.
    - **`NAPredicateError`**: Dedicated error code for NA values in boolean contexts, enabling robust logic in `filter()` and `if` expressions.
    - **Strict Guards**: Enhanced logical and comparison operators to raise errors on NA instead of silent propagation.
    - **Optimized Math**: Verified `na_ignore` semantics across all core math transforms (`abs`, `log`, `sqrt`, `exp`, `pow`) and aggregations (`min`, `max`, `sum`, `mean`).
- **Complete Removal of Null**:
    - The `null` keyword and `VNull` type have been completely removed from the language grammar and AST.
    - Unified all previous "nullable" return paths (e.g., missing env vars, empty nodes) to use typed `NA` values.
    - Replaced `is_null()` with `is_na()` as the universal missingness predicate.

### Model Interoperability & Native Scoring
- **Standardized PMML Interchange**:
    - Transitioned to JPMML as the canonical scoring authority via a robust, CSV-based bridge.
    - **Native Ensemble Scoring**: Added native OCaml support for Random Forests, XGBoost, and LightGBM models.
    - **Categorical Expansion**: Implemented automatic dummy-variable/one-hot expansion and interaction term (`:`) resolution in the native `lm()` and `predict()` engines.
    - **`fit_stats()` API**: Unified goodness-of-fit statistics (R², AIC, BIC) into a single, language-agnostic DataFrame output.
- **Native ONNX Inference**:
    - Full support for `^onnx` serialization and native OCaml scoring via `onnxruntime` FFI.
    - Automated feature mapping, metadata extraction, and multi-input/output tensor support.
    - High-performance, memory-safe session management with OCaml GC integration.

### Language Robustness & Interop
- **Strict Equality Semantics**:
    - Enforced scalarity for `==` and `!=`. These now require explicit broadcasting (`.==`) for collections to prevent silent logic errors.
    - **`identical(a, b)`**: New core builtin for deep structural equality of complex objects.
- **Enhanced Data Operations**:
    - **`dataframe()` Constructor**: Added support for Dictionary-based construction and automatic scalar recycling.
    - **NSE Safety**: Implemented guarded NSE transformation to prevent unexpected lambda-wrapping of non-NSE builtins.
- **String Column Extraction**: Enhanced `pull()` and column helpers to support `VString` arguments for extraction of special-character column names.

### Project, CI & Test Infrastructure
- **Strict Dependency Declaration**:
    - Finalized the removal of implicit Nix package injection. All requirements must be explicitly listed in `tproject.toml`.
    - Added interactive injection prompts and `TLANG_AUTO_ADD_PIPELINE_DEPS` for CI automation.
- **Environment Stability**:
    - Standardized Nixpkgs pinning via `RSTATS-NIX-DATE` for reproducible, cache-friendly builds.
    - **Serialization Integrity**: Introduced mandatory MD5 digests for all serialized artifacts.
- **CI/CD Stabilization**:
    - Refactored `t_demos` into 30+ dedicated per-demo workflows.
    - Optimized the core test suite to use static interrogation and modern mocks, achieving a stable baseline of **1837/1837** tests passed.
    - Enhanced the test runner with aggregated failure summaries.

### Bug Fixes & Refinements
- **REPL Stability**: Corrected a documentation comment collision in `repl.ml` that was causing compilation errors during scale-wide refactors.
- **Python Node Emitter**: Refined the auto-return logic to ignore trailing comments and whitespace, preventing silent `None` results.
- **Grouped Mutate**: Fixed a regression where assigning constant scalars to grouped DataFrames would fail.
- **Interaction Resolution**: Restored and verified interaction term (`:`) resolution in native linear model scoring.

## Version 0.51.2

**Status**: Beta  
**Release Date**: 2026-03-28

### Features & UX

- **Immutable Update Lenses**: F inalized the lens system with support for deep surgical updates to Dictionaries and DataFrames.
    - Introduced **`modify()`**: A variadic builtin for applying multiple lens transformations in a single pass.
    - Updated **`compose()`**: Now variadic, allowing any number of lenses to be chained into a single declarative path.
    - **Orchestration Lenses**: Added `node_lens()` and `env_var_lens()` for inspecting and modifying Pipeline node results and environment variables.
    - **Collections & Filtering**: Added **`idx_lens(i)`** for positional access in Lists/Vectors, **`row_lens(i)`** for specific DataFrame row targeting, and **`filter_lens(p)`** for predicate-based focus on elements and rows.
    - **Vectorization**: Lenses are fully vectorized, allowing transformations to penetrate nested DataFrames across all rows automatically.
- **`rm()` Function**: New core language feature for removing variables from the environment. Supports symbols, strings, and list-based removal (e.g., `rm(x, y)`, `rm("z")`, `rm(list = vars)`).
- **Asynchronous Build Progress**: Implemented a new streaming build progress reporter in the terminal. Pipeline builds now show real-time "building" and "built" alerts for each node, with high-noise Nix logs filtered by default.
- **First-Class Serializer System**: Introduced a robust, type-safe serialization layer for polyglot pipelines.
    - **Serializer Registry**: Added the `^` symbol prefix for resolving built-in serializers from a centralized registry (e.g., `^csv`, `^arrow`, `^pmml`, `^json`, `^text`).
    - **VSerializer Type**: Serializers are now first-class records containing metadata and language-specific snippets for R and Python.
    - **Foreign Code Enforcement**: Custom polyglot serializers now require foreign code blocks (`<{ ... }>`) for reader/writer snippets, ensuring syntactic separation between T and injected code.
    - **Static Coherence Checks**: The pipeline builder now performs build-time verification to ensure producer and consumer formats match, catching data interchange errors before execution.
- **Error Visibility**: When a pipeline fails, the summary now correctly reports the count of errored nodes (e.g., "[1 node errored]").
- **REPL Interface**: Added a new `t_make()` builtin to the REPL. It defaults to building `src/pipeline.t` and supports optional named arguments (e.g., `max_jobs`, `max_cores`) that pass through to the underlying Nix build.
- **Improved Name Errors**: Added fuzzy matching to `NameError` reporting with "Did you mean ...?" suggestions when an unbound variable is accessed.
- **Pattern Matching (match)**: Introduced the `match` expression for declarative list and error destructuring. Includes support for head/tail patterns, `Error { msg }` patterns, and automatic error propagation for unhandled error values.
- **REPL Responsiveness**: Added explicit `flush stderr` after variable reassignment (`:=`) warnings to ensure they appear promptly in the REPL.
- **Pipeline Sandboxing**: Enhanced `read_node()` to automatically fall back to environment variables (`T_NODE_<name>`) when build logs are unavailable. This enables `read_node` to work inside Nix build sandboxes (e.g., within Quarto nodes or nested pipeline steps) and provides automatic deserialization for Arrow, JSON, and PMML artifacts based on class hints.

### Improved

- **Build Log Inspection**: `read_log()` now returns the Nix build log as a `VString` instead of printing directly. This allows the log to be captured as a variable or formatted with `cat()`.
- **String Printing**: `print()` and `cat()` now correctly handle literal newlines and escape sequences in strings and shell results, ensuring `?<{ls -l}>` and logs display correctly.
- **Project Initialization**: Better `t init` interactive prompts and project scaffolding templates. The `t init` command now defaults to the version of the T binary being used.
- **CLI Interface**: Renamed `t init package` and `t init project` subcommands to `t init --package` and `t init --project` flags for better clarity.
- **Python Node FFI**: Improved dependency handling in `pyn()`. Pipeline nodes are now correctly provided as global variables in the Python runtime.
- **Nix Sandbox Robustness**: Added missing `import os` to Python serialization snippets, ensuring standard library access in the Nix sandbox.
- **CI Reliability**: `t update` now automatically handles untracked `flake.nix` in Git repositories when running in a CI environment (`CI=true`).
- **Nix Support**: Added help for experimental flags and trusted user configuration in `docs/installation.md`.

### Fixed

- **Design Consistency**: Standardized all documentation and examples to reinforce the "**Data Frame First**" principle for function arguments, ensuring compatibility with T's functional piping (`|>`) patterns.
- **Typos**: Fixed documentation typos (e.g., "sterilization" -> "serialization").
- **Example Revisions**: Synchronized all pipeline demos in `t_demos` and `examples/` with the latest first-class serializer system and `^`-prefix notation.
- **Error Message Clarity**: Improved error messages for immutable variable reassignment with actionable suggestions (`Use ':=' to overwrite or rm() to delete the variable`).
- **Global Guide Alignment**: Performed a repository-wide sweep to remove legacy version strings and hardcoded formatting in installation and project guides.

Version history and roadmap for the T programming language.

## [0.51.1] - 2026-03-21

**Status**: Beta
**Release Date**: 21st of March 2026

### Features & CLI

- **New Command**: Introduced `t upgrade` to automatically update projects to the latest T version and refresh the `rstats-on-nix` nixpkgs date.
- **Centralized Versioning**: Version is now managed in a single `VERSION` file and propagated across the project.

### Bug Fixes & Improvements

- **Package Management**: Fixed issues in `t update` and related flake generation logic.
- **Quarto Integration**: Fixed `read_node` substitution in Quarto reports to prevent syntax errors in R/Python chunks.
- **Testing**: Resolved failures in Quarto pipeline tests and improved CI reliability.

## Version 0.51.0 — First Public Release

**Status**: Alpha — Syntax and semantics frozen  
**Release Date**: February 2026

### Package Manager (`t update`)

- **Versioning sync**: `t update` now generates a `flake.nix` that points to this version by default.
- **Improved defaults**: Projects without an explicit `min_version` now use 0.51.0.

### Language Core

✅ **Implemented**:

- Lexer and parser (Menhir)
- Tree-walking interpreter
- Expression-oriented evaluation
- Immutable values
- Dynamic typing with runtime checks
- First-class functions and closures
- List comprehensions
- **Non-Standard Evaluation (NSE)**: Dollar-prefix column references (`$column_name`) for concise data manipulation

### NSE (Non-Standard Evaluation)

✅ **Implemented**:

- Dollar-prefix syntax: `$column_name` for column references
- Auto-transformation: `$age > 30` → `\(row) row.age > 30`
- Named-arg syntax: `summarize($total = sum($amount))`, `mutate($bonus = $salary * 0.1)`
- Works with all data verbs: `select`, `filter`, `mutate`, `arrange`, `group_by`, `summarize`

### Data Types

✅ **Implemented**:

- Scalars: Int, Float, Bool, String
- Collections: List, Dict
- DataFrames (Arrow-backed)
- Vectors (typed arrays)
- NA (typed missing values)
- Error (structured errors, not exceptions)
- Pipeline (DAG execution)
- Intent (LLM metadata)
- Formula (statistical modeling)
- NA

### Operators

✅ **Implemented**:

- Arithmetic: `+`, `-`, `*`, `/`, `%`
- Comparison: `==`, `!=`, `<`, `>`, `<=`, `>=`
- Logical: `and`, `or`, `not`
- Pipe: `|>` (conditional, short-circuits on error)
- Maybe-pipe: `?|>` (always forwards, including errors)
- Formula: `~` (for regression models)

### Standard Library

✅ **Core Package**:

- `print`, `pretty_print`, `type`, `length`, `head`, `tail`
- `map`, `filter`, `sum`, `seq`
- `is_error`

✅ **Base Package**:

- `error`, `error_code`, `error_message`, `error_context`
- `assert`
- `NA`, `na_int`, `na_float`, `na_bool`, `na_string`, `is_na`

✅ **Math Package**:

- `sqrt`, `abs`, `log`, `exp`, `pow`
- `min`, `max`

✅ **Stats Package**:

- `mean`, `sd`, `quantile`, `cor` (with `na_rm` parameter)
- `lm` (linear regression: `y ~ x`)

✅ **DataFrame Package**:

- `read_csv` (with `separator`, `skip_lines`, `skip_header`, `clean_colnames`)
- `write_csv`
- `nrow`, `ncol`, `colnames`
- `clean_colnames` (symbol expansion, diacritics, snake_case, collision resolution)

✅ **Colcraft Package** (Data Verbs):

- `select`, `filter`, `mutate`, `arrange`
- `group_by`, `summarize`, `ungroup`
- **Window functions**:
  - Ranking: `row_number`, `min_rank`, `dense_rank`, `cume_dist`, `percent_rank`, `ntile`
  - Offset: `lag`, `lead`
  - Cumulative: `cumsum`, `cummin`, `cummax`, `cummean`, `cumall`, `cumany`

✅ **Pipeline Package**:

- `pipeline_nodes`, `pipeline_deps`, `pipeline_node`, `pipeline_run`

✅ **Explain Package**:

- `explain`, `explain_json`
- `intent_fields`, `intent_get`

### Features

✅ **Error Handling**:

- Errors as values (not exceptions)
- Railway-oriented programming with `|>` and `?|>`
- Actionable error messages with suggestions

✅ **NA Handling**:

- Explicit NA (typed: `na_int()`, etc.)
- No automatic propagation
- `na_rm` parameter for aggregations
- Window functions handle NA gracefully

✅ **Pipelines**:

- DAG-based execution
- Automatic dependency resolution
- Deterministic order
- Cycle detection
- Introspection

✅ **Cross-Language Model Interchange (PMML)**:

- Native PMML parser and evaluator in OCaml
- Seamless import of models from R (`lm`) and Python (`scikit-learn`)
- `broom`-style tidy summaries (`summary()`, `fit_stats()`) for imported models
- Native high-performance prediction in T without runtime language dependencies

✅ **Intent Blocks**:

- Structured metadata for LLM collaboration
- Document assumptions, constraints, goals
- Machine-readable format

✅ **Arrow Integration & Data Formats**:

- Zero-copy columnar storage
- CSV reading via Arrow C GLib
- **Parquet & Feather Support**: Full native read/write for Arrow-backed files
- Dual-path operations (native + fallback)
- `explain(df)` surfaces whether a DataFrame is still on the native Arrow path (`storage_backend`, `native_path_active`)
- Supported structural rebuilds now try to stay Arrow-backed by rematerializing into a fresh native table
- **Current limitation**: unsupported builder paths (for example NA-only, factor, list, date, or datetime columns) still fall back to pure OCaml/T storage

✅ **Reproducibility**:

- Nix flakes for dependency management
- Deterministic execution
- Frozen syntax and semantics

### REPL

✅ **Implemented**:

- Interactive read-eval-print loop
- Multiline input support
- Persistent environment
- Auto-loading of standard library

### Testing

✅ **Implemented**:

- Unit tests (OCaml)
- Golden tests (T vs R comparison)
- Example-based tests

### Package Management & Flakes (Bug fixes)

✅ **Implemented**:

- `T_PACKAGE_PATH` flake configurations export the exact built derivations rather than raw source maps
- Packages dynamically bundle the local `src/` and `help/` directories instead of silently failing context
- `t-lang` compiler successfully stripped out of packages' default recursive `buildInputs` dependencies
- `help()` UX fallback bypasses closures gracefully by searching locally bound environment lambda variables

### Documentation

✅ **Implemented** (this release):

- README with quick start
- Getting Started guide
- Installation guide
- API Reference (all packages)
- Language Overview
- Data Manipulation Examples
- Pipeline Tutorial
- Architecture guide
- Contributing guide
- Development guide
- Comprehensive Examples
- Error Handling guide
- Reproducibility guide
- LLM Collaboration guide
- FAQ
- Troubleshooting guide
- Changelog (this file)
- **Model Interchange & PMML**: Documentation for cross-language model support and broom-style outputs for imported models.
- **Improved Data Inspection**: Enhanced `glimpse()` documentation for quick DataFrame summaries.


# FILE: docs/code-of-ethics.md

## 1. Origin

This Code of Ethics is adapted from the SQLite Project’s *Code of Ethics* 
([https://sqlite.org/codeofethics.html](https://sqlite.org/codeofethics.html)). 
The SQLite document draws inspiration from Chapter 4 (“Instruments of Good Works”) 
of *The Rule of St. Benedict*, a text that has guided communities for over 
fifteen centuries.

Like the original, this adaptation is not intended to function as a procedural 
code of conduct or an enforcement framework. Rather, it serves as a statement 
of ethical intent and personal commitment.

## 2. A Note from the Maintainer

Although I am not a Christian, I find the principles expressed in this rule 
thoughtful and constructive. The text emphasizes humility, self-restraint, 
honesty, patience, forgiveness, and care for others, values that transcend 
religious context and remain relevant in modern collaborative work.

This Code of Ethics reflects a commitment to:

* Treat others with respect and dignity
* Respond to disagreement without hostility
* Avoid personal attacks, deception, or bad faith behavior
* Act with integrity and intellectual honesty
* Support and assist others where possible

These principles are not imposed on contributors as a condition of participation.
Rather, they represent a personal commitment by the maintainer regarding how this 
project will be conducted and how others will be treated.

This document is therefore best understood not as a regulatory instrument, 
but as a public statement of values guiding the stewardship of the project.

## 3. The Rule

1. First of all, love the Lord God with your whole heart, your whole soul, and your whole strength.
2. Then, love your neighbor as yourself.
3. Do not murder.
4. Do not commit adultery.
5. Do not steal.
6. Do not covet.
7. Do not bear false witness.
8. Honor all people.
9. Do not do to another what you would not have done to yourself.
10. Deny oneself in order to follow Christ.
11. Chastise the body.
12. Do not become attached to pleasures.
13. Love fasting.
14. Relieve the poor.
15. Clothe the naked.
16. Visit the sick.
17. Bury the dead.
18. Be a help in times of trouble.
19. Console the sorrowing.
20. Be a stranger to the world's ways.
21. Prefer nothing more than the love of Christ.
22. Do not give way to anger.
23. Do not nurse a grudge.
24. Do not entertain deceit in your heart.
25. Do not give a false peace.
26. Do not forsake charity.
27. Do not swear, for fear of perjuring yourself.
28. Utter only truth from heart and mouth.
29. Do not return evil for evil.
30. Do no wrong to anyone, and bear patiently wrongs done to yourself.
31. Love your enemies.
32. Do not curse those who curse you, but rather bless them.
33. Bear persecution for justice's sake.
34. Be not proud.
35. Be not addicted to wine.
36. Be not a great eater.
37. Be not drowsy.
38. Be not lazy.
39. Be not a grumbler.
40. Be not a detractor.
41. Put your hope in God.
42. Attribute to God, and not to self, whatever good you see in yourself.
43. Recognize always that evil is your own doing, and to impute it to yourself.
44. Fear the Day of Judgment.
45. Be in dread of hell.
46. Desire eternal life with all the passion of the spirit.
47. Keep death daily before your eyes.
48. Keep constant guard over the actions of your life.
49. Know for certain that God sees you everywhere.
50. When wrongful thoughts come into your heart, dash them against Christ immediately.
51. Disclose wrongful thoughts to your spiritual mentor.
52. Guard your tongue against evil and depraved speech.
53. Do not love much talking.
54. Speak no useless words or words that move to laughter.
55. Do not love much or boisterous laughter.
56. Listen willingly to holy reading.
57. Devote yourself frequently to prayer.
58. Daily in your prayers, with tears and sighs, confess your past sins to God, and amend them for the future.
59. Fulfill not the desires of the flesh; hate your own will.
60. Obey in all things the commands of those whom God has placed in authority over you even though they (which God forbid) should act otherwise, mindful of the Lord's precept, "Do what they say, but not what they do."
61. Do not wish to be called holy before one is holy; but first to be holy, that you may be truly so called.
62. Fulfill God's commandments daily in your deeds.
63. Love chastity.
64. Hate no one.
65. Be not jealous, nor harbor envy.
66. Do not love quarreling.
67. Shun arrogance.
68. Respect your seniors.
69. Love your juniors.
70. Pray for your enemies in the love of Christ.
71. Make peace with your adversary before the sun sets.
72. Never despair of God's mercy.

# FILE: docs/contributing.md

# Contributing to T

Thank you for your interest in contributing to T! This guide will help you get started.

## Table of Contents

- [Code of Ethics](#code-of-ethics)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Submitting Changes](#submitting-changes)
- [Review Process](#review-process)

---

## Code of Ethics

This project follows a [Code of Ethics](code-of-ethics.md) adapted from the SQLite project.
Please review it to understand the detailed ethical guidelines and expected behavior.

---

## How Can I Contribute?

### Reporting Bugs

**Before submitting**, check if the issue already exists in [GitHub Issues](https://github.com/b-rodrigues/tlang/issues).

**When submitting**:
1. Use a clear, descriptive title
2. Describe the exact steps to reproduce
3. Provide sample code and data (if applicable)
4. Include your environment (OS, Nix version, OCaml version)
5. Attach error messages and stack traces

**Example**:
```markdown
**Bug**: `mean()` returns incorrect result for large floats

**Steps**:
1. Start REPL
2. Run: `mean([1e10, 1e10, 1e10])`
3. Expected: `1e10`, Got: `9.99999e9`

**Environment**:
- OS: Ubuntu 22.04
- Nix: 2.13.3
- OCaml: 4.14.1
```

### Suggesting Features

**Before suggesting**, consider:
- Is it aligned with T's design goals (reproducibility, explicitness, data analysis)?
- Is it too broad or general-purpose?
- Could it be a library instead of core language feature?

**When suggesting**:
1. Clearly describe the problem it solves
2. Provide concrete examples
3. Discuss alternatives

### Contributing Code

We welcome:
- Bug fixes
- New standard library functions
- Performance improvements
- Documentation improvements
- Test coverage expansion

**Good first issues** are tagged with `good-first-issue` in GitHub.

### Improving Documentation

Documentation contributions are highly valued:
- Fix typos and grammatical errors
- Add examples to existing docs
- Write tutorials for common workflows
- Improve API reference clarity

---

## Development Setup

See the [Development Guide](development.md) for detailed setup instructions.

**Quick Start**:

1. **Install Nix**: Follow the [Nix Installation Guide](nix-installation.md).
2. **Clone and Build**:
   ```bash
   git clone https://github.com/b-rodrigues/tlang.git
   cd tlang
   nix develop
   dune build
   dune runtest
   ```

---

## Project Structure

```
tlang/
├── src/
│   ├── ast.ml              # AST definition
│   ├── lexer.mll           # Lexer (ocamllex)
│   ├── parser.mly          # Parser (Menhir)
│   ├── eval.ml             # Evaluator
│   ├── repl.ml             # REPL implementation
│   ├── arrow/              # Arrow FFI bindings
│   │   ├── arrow_ffi.ml
│   │   └── arrow_stubs.c
│   ├── ffi/                # Other FFI utilities
│   └── packages/           # Standard library
│       ├── base/           # Errors, NA, assertions
│       ├── core/           # Functional utilities
│       ├── math/           # Math functions
│       ├── stats/          # Statistics
│       ├── dataframe/      # DataFrame operations
│       ├── colcraft/       # Data verbs
│       ├── pipeline/       # Pipeline introspection
│       └── explain/        # Debugging tools
├── tests/                  # Test suite
│   ├── unit/               # Unit tests
│   ├── golden/             # Golden tests (T vs R)
│   └── examples/           # Example programs
├── docs/                   # Documentation
├── examples/               # Example T programs
├── scripts/                # Development scripts
├── flake.nix               # Nix flake configuration
├── dune-project            # Dune configuration
└── Makefile                # Convenience targets
```

---

## Coding Standards

### OCaml Style

Follow standard OCaml conventions:

**Naming**:
- `snake_case` for functions and variables
- `PascalCase` for modules and types
- `SCREAMING_CASE` for constants

**Formatting**:
```ocaml
(* Use ocamlformat for automatic formatting *)
let eval env expr =
  match expr with
  | Int n -> VInt n
  | Float f -> VFloat f
  | Ident name -> Environment.lookup env name
  | BinOp (op, left, right) ->
      let v_left = eval env left in
      let v_right = eval env right in
      eval_binop op v_left v_right
  | _ -> failwith "Not implemented"
```

**Comments**:
- Use `(* OCaml comments *)` for implementation notes
- Document complex logic
- Explain "why" not "what"

**Pattern Matching**:
- Exhaustively match all cases
- Use `_` for catch-all only when intentional
- Avoid deeply nested matches (extract functions)

### T Language Style

**Example programs** should demonstrate best practices:

```t
-- Good: Clear variable names, explicit NA handling
customers = read_csv("data.csv", clean_colnames = true)
avg_age = mean(customers.age, na_rm = true)

-- Bad: Cryptic names, implicit NA behavior
c = read_csv("data.csv")
a = mean(c.age)  -- Errors if NA present
```

**Documentation**:
- Include docstrings for new functions
- Provide usage examples
- Document parameters and return values

---

## Testing Requirements

### Unit Tests

Located in `tests/unit/`.

**Example** (`tests/unit/test_mean.ml`):
```ocaml
let test_mean_basic () =
  let result = Stats.mean [VInt 1; VInt 2; VInt 3] false in
  assert (result = VFloat 2.0)

let test_mean_with_na () =
  let result = Stats.mean [VInt 1; VNA NAInt; VInt 3] true in
  assert (result = VFloat 2.0)

let tests = [
  ("mean_basic", test_mean_basic);
  ("mean_with_na", test_mean_with_na);
]
```

### Golden Tests

Located in `tests/golden/`.

Compare T output against R:

**T Program** (`tests/golden/mean.t`):
```t
print(mean([1, 2, 3, 4, 5]))
```

**R Script** (`tests/golden/mean.R`):
```r
cat(mean(c(1, 2, 3, 4, 5)), "\n")
```

**Run**:
```bash
dune exec src/repl.exe < tests/golden/mean.t > t_output.txt
Rscript tests/golden/mean.R > r_output.txt
diff t_output.txt r_output.txt
```

### Test Coverage

**Required**:
- All new functions must have unit tests
- Bug fixes must include regression tests
- Performance claims must include benchmarks

**Recommended**:
- Test edge cases (empty lists, NA values, errors)
- Test cross-platform behavior (Linux, macOS)
- Test integration with existing features

### Running Tests

```bash
# All tests
dune runtest

# Specific test
dune runtest tests/unit/test_mean.ml

# Verbose output
dune runtest --verbose

# Watch mode (re-run on changes)
dune runtest --watch
```

---

## Submitting Changes

### Workflow

1. **Fork** the repository
2. **Clone** your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/tlang.git
   ```
3. **Create a branch**:
   ```bash
   git checkout -b feature/my-feature
   ```
4. **Make changes**:
   - Write code
   - Add tests
   - Update documentation
5. **Test**:
   ```bash
   dune build
   dune runtest
   ```
6. **Commit**:
   ```bash
   git add .
   git commit -m "Add feature: description"
   ```
7. **Push**:
   ```bash
   git push origin feature/my-feature
   ```
8. **Open a Pull Request** on GitHub

### Commit Messages

Follow conventional commit format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting, no code change
- `refactor`: Code refactor
- `test`: Add or fix tests
- `chore`: Build, CI, tooling

**Examples**:
```
feat(stats): Add median function

Implements median via quantile(0.5). Supports na_rm parameter.

Closes #42
```

```
fix(eval): Fix closure environment capture

Closures were capturing global env instead of local env.
This caused incorrect behavior in nested functions.
```

### Pull Request Guidelines

**Title**: Clear and descriptive
```
Add median function to stats package
```

**Description**: Include:
- What changed and why
- Related issue numbers (`Fixes #42`, `Closes #17`)
- Testing done
- Screenshots (for UI/output changes)

**Example**:
```markdown
## Summary
Adds `median()` function to stats package.

## Changes
- Implement median as `quantile(data, 0.5)`
- Add unit tests
- Update API reference documentation

## Testing
- Unit tests pass
- Golden test against R's `median()`
- Tested with NA values (na_rm parameter)

Fixes #42
```

**Checklist**:
- [ ] Code follows style guidelines
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] All tests pass
- [ ] Commit messages are clear

---

## Review Process

### What Reviewers Look For

1. **Correctness**: Does it work as intended?
2. **Testing**: Are changes adequately tested?
3. **Style**: Does it follow project conventions?
4. **Documentation**: Are changes documented?
5. **Scope**: Is the change focused and minimal?
6. **Backward Compatibility**: Does it break existing code?

### Addressing Feedback

- Be responsive to comments
- Don't take criticism personally
- Ask questions if feedback is unclear
- Make requested changes promptly
- Mark conversations as resolved when addressed

### Approval and Merge

- **1 approval required** for most changes
- **2 approvals required** for breaking changes or core features
- Maintainers will merge once approved
- Squash-merge is used to keep history clean

---

## Adding New Standard Library Functions

### Process

1. **Choose a package**: `base`, `core`, `math`, `stats`, `dataframe`, `colcraft`, `pipeline`, or `explain`
2. **Create function file**: `src/packages/<package>/<function_name>.ml` or `.t`
3. **Implement function**:
   ```ocaml
   (* src/packages/stats/median.ml *)
   let median values na_rm =
     Stats.quantile values 0.5 na_rm
   ```
4. **Register in package loader** (if needed)
5. **Add tests**: `tests/unit/test_median.ml`
6. **Update docs**: `docs/api-reference.md`
7. **Add example**: `examples/median_example.t`

### Function Signature Guidelines

**Parameters**:
- Required parameters first
- Optional parameters (e.g., `na_rm`) last
- Use named arguments for clarity

**Return values**:
- Return values, not side effects (when possible)
- Use `VError` for errors, not OCaml exceptions
- Document return type in comments

**Error handling**:
```ocaml
(* Good: Return VError *)
if List.length values = 0 then
  VError { code = "ValueError"; message = "Empty list"; ... }
else
  (* Compute result *)

(* Bad: Raise exception *)
if List.length values = 0 then
  failwith "Empty list"
```

---

## Getting Help

### Communication Channels

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: General questions, ideas, show-and-tell
- **Pull Requests**: Code review and technical discussion

### Asking Good Questions

Include:
- What you're trying to do
- What you've tried
- Specific error messages
- Minimal reproducible example
- Your environment (OS, versions)

**Example**:
```markdown
I'm trying to add a new window function `row_min()` but getting a type error:

Error: This expression has type 'a list but an expression was expected of type Vector.t

Code:
```ocaml
let row_min values =
  (* ... *)
```

I've looked at `row_number.ml` but can't figure out where the conversion happens.

Environment: Ubuntu 22.04, OCaml 4.14.1
```

---

## Recognition

Contributors are recognized in:
- GitHub contributor graph
- Release notes for significant contributions
- `CONTRIBUTORS.md` file (coming soon)

---

## License

By contributing, you agree that your contributions will be licensed under the [EUPL v1.2](../LICENSE).

---

**Ready to contribute?** Check out [good first issues](https://github.com/b-rodrigues/tlang/labels/good-first-issue) or dive into the [Development Guide](development.md)!


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
model.coefficients.age    -- coefficient for age
model.r_squared           -- R² goodness of fit
model.nobs                -- number of observations
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


# FILE: docs/demos.md

# T Pipeline Demos

This page lists real-world T projects that demonstrate the power of polyglot, reproducible orchestration. Most of these demos are available in the [tstats-project/t_demos](https://github.com/tstats-project/t_demos) repository.

## Visualization & Reporting

### [Plotting & Visual Metadata Capture](plotting.html)
- **Repo**: `plotting_pipeline_t`
- **Description**: Demonstrates how T captures structural metadata from `ggplot2` (R) and `matplotlib` (Python).
- **Key Features**: Polyglot plots, metadata extraction, Nix-reproducible charts.

### [Quarto Literate Programming](literate-programming-quarto.html)
- **Repo**: `quarto_test_t`
- **Description**: Shows how to embed T pipeline results in a Quarto report.
- **Key Features**: Auto-substitution of `read_node()`, Nix-built reports.

## Statistical Modeling

### [Model Comparison: R vs Python](models.html)
- **Repo**: `model_comparison_t`
- **Description**: Compares GLM results across R and Python nodes within the same pipeline.
- **Key Features**: Concurrent R and Python environments, PMML interchange.

### [Titanic Survival](pmml_tutorial.html)
- **Repo**: `glm_titanic_t`
- **Description**: A classic statistical modeling pipeline using the Titanic dataset.
- **Key Features**: Data cleaning, logistic regression, result serialization.

## Advanced Orchestration

### [ONNX & PMML Interchange](pmml_tutorial.html)
- **Repo**: `onnx_exchange_t` / `pmml_interchange_t`
- **Description**: Moving trained models between high-level languages and T's native scoring engine.
- **Key Features**: `predict()` across language boundaries, standardized model storage.

### [Lenses & Dynamic Pipelines](lens.html)
- **Repo**: `deep_data_lenses_t` / `dynamic_pipeline_operator_t`
- **Description**: Demonstrates functional updates to immutable configurations and dynamic DAG generation.
- **Key Features**: Pipeline-as-code, functional composition.

## Meta-programming & Introspection

### [Dynamic Lookup & Symbols](metaprogramming.html)
- **Repo**: `get_sym_demo_t`
- **Description**: Showcases runtime variable lookup and symbol construction for dynamic orchestration.
- **Key Features**: `get()`, `sym()`, dynamic node access.

---

## Running the Demos

To try any of these demos locally:

1.  **Clone the demos repository**:
    ```bash
    git clone https://github.com/tstats-project/t_demos
    cd t_demos/<project_name>
    ```
2.  **Bootstrap the T environment**:
    If you don't have the `t` command installed yet, use Nix to get a temporary shell containing it:
    ```bash
    nix shell github:b-rodrigues/tlang
    ```
3.  **Synchronize dependencies**:
    T uses `tproject.toml` to manage dependencies. Run this to generate the project's local `flake.nix`:
    ```bash
    t update
    ```
    Once `t update` is complete, **exit the temporary shell**:
    ```bash
    exit
    ```
4.  **Enter the project shell**:
    Now use the project-specific environment generated by T:
    ```bash
    nix develop
    ```
5.  **Run the pipeline**:
    ```bash
    t run src/pipeline.t
    ```


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
-- Error(NAPredicateError: Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.)
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

**Solution**: Use separate print statements or `str_string()` for manual conversion.

```t
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


# FILE: docs/examples.md

# Comprehensive Examples

Real-world examples demonstrating T's capabilities for data analysis and manipulation.

## Table of Contents

- [Basic Data Analysis](#basic-data-analysis)
- [Data Cleaning](#data-cleaning)
- [Statistical Analysis](#statistical-analysis)
- [Group Operations](#group-operations)
- [Window Functions](#window-functions)
- [Reproducible Pipelines](#reproducible-pipelines)
- [Error Handling Patterns](#error-handling-patterns)
- [LLM Collaboration](#llm-collaboration)

---

## Basic Data Analysis

### Loading and Inspecting Data

```t
-- Load customer data
customers = read_csv("customers.csv", clean_colnames = true)

-- Inspect structure
nrow(customers)        -- 1000
ncol(customers)        -- 5
colnames(customers)    -- ["name", "age", "city", "purchases", "active"]

-- View sample
head(customers.age, 10)
```

### Basic Statistics

```t
-- Summary statistics
mean_age = mean(customers.age, na_rm = true)
sd_age = sd(customers.age, na_rm = true)
median_purchases = quantile(customers.purchases, 0.5, na_rm = true)

print("Average age: " + str_string(mean_age))
print("Age SD: " + str_string(sd_age))
print("Median purchases: " + str_string(median_purchases))

-- Distribution analysis
q25 = quantile(customers.purchases, 0.25, na_rm = true)
q75 = quantile(customers.purchases, 0.75, na_rm = true)
iqr = q75 - q25

print("IQR: " + str_string(iqr))
```

### Simple Filtering and Selection

```t
-- Active customers only
active = customers |> filter($active == true)

-- High-value customers
high_value = customers 
  |> filter($purchases > 100)
  |> select($name, $purchases)

-- Age groups
young = customers |> filter($age < 30)
mature = customers |> filter($age >= 30 and $age < 50)
senior = customers |> filter($age >= 50)

print("Young customers: " + str_string(nrow(young)))
print("Mature customers: " + str_string(nrow(mature)))
print("Senior customers: " + str_string(nrow(senior)))
```

---

## Data Cleaning

### Handling Missing Values

```t
-- Check for NA
sales = read_csv("sales.csv")

-- Count NA per column
na_count_revenue = length(filter(sales.revenue, \(x) is_na(x)))
na_count_cost = length(filter(sales.cost, \(x) is_na(x)))

print("NA in revenue: " + str_string(na_count_revenue))
print("NA in cost: " + str_string(na_count_cost))

-- Remove rows with any NA
clean = sales |> filter(
  not is_na($revenue) and not is_na($cost)
)

-- Or use na_rm in calculations
total_revenue = sum(sales.revenue, na_rm = true)
avg_revenue = mean(sales.revenue, na_rm = true)
```

### Column Name Cleaning

```t
-- Messy column names
raw = read_csv("messy_data.csv")
colnames(raw)
-- ["Product ID", "Sales (€)", "Growth%", "2023 Total"]

-- Clean names
clean = read_csv("messy_data.csv", clean_colnames = true)
colnames(clean)
-- ["product_id", "sales_euro", "growth_percent", "x_2023_total"]

-- Now accessible with dot notation
avg_sales = mean(clean.sales_euro, na_rm = true)
```

### Data Type Conversions

```t
-- Assuming string to number conversion functions exist
-- (In T, types are inferred from CSV, but you can transform)

-- Create derived columns with correct types
data = data |> mutate("price_num", \(row) parse_float(row.price_str))

-- Boolean flags
data = data |> mutate("is_premium", \(row) row.price > 100)

-- Categorical to numeric
data = data |> mutate("region_code", \(row) 
  if (row.region == "North") 1
  else if (row.region == "South") 2
  else if (row.region == "East") 3
  else 4
)
```

### Outlier Detection and Removal

```t
-- Calculate bounds
values = df.salary
q25 = quantile(values, 0.25, na_rm = true)
q75 = quantile(values, 0.75, na_rm = true)
iqr = q75 - q25
lower_bound = q25 - 1.5 * iqr
upper_bound = q75 + 1.5 * iqr

-- Remove outliers
cleaned = df |> filter(
  $salary >= lower_bound and $salary <= upper_bound
)

print("Original rows: " + str_string(nrow(df)))
print("After outlier removal: " + str_string(nrow(cleaned)))
```

---

## Statistical Analysis

### Correlation Analysis

```t
-- Load data
economics = read_csv("economics.csv")

-- Compute correlation
cor_gdp_unemployment = cor(
  economics.gdp, 
  economics.unemployment_rate,
  na_rm = true
)

print("GDP vs Unemployment: r = " + str_string(cor_gdp_unemployment))

-- Multiple correlations
cor_consumption_income = cor(economics.consumption, economics.income, na_rm = true)
cor_savings_income = cor(economics.savings, economics.income, na_rm = true)

print("Consumption vs Income: r = " + str_string(cor_consumption_income))
print("Savings vs Income: r = " + str_string(cor_savings_income))
```

### Linear Regression

```t
-- Simple regression
advertising = read_csv("advertising.csv")

model = lm(
  data = advertising,
  formula = sales ~ ad_spend
)

-- Inspect model
print("Slope: " + str_string(model.slope))
print("Intercept: " + str_string(model.intercept))
print("R²: " + str_string(model.r_squared))
print("N: " + str_string(model.n))

-- Manual prediction
predict = \(x) model.intercept + model.slope * x
predicted_sales = predict(5000)

print("Predicted sales for $5000 ad spend: " + str_string(predicted_sales))
```

### Hypothesis Testing (Manual t-test example)

```t
-- Compare two groups
group_a = df |> filter($treatment == "A") |> \(d) d.outcome
group_b = df |> filter($treatment == "B") |> \(d) d.outcome

-- Calculate means and SDs
mean_a = mean(group_a, na_rm = true)
mean_b = mean(group_b, na_rm = true)
sd_a = sd(group_a, na_rm = true)
sd_b = sd(group_b, na_rm = true)

-- Effect size (Cohen's d)
pooled_sd = sqrt((sd_a * sd_a + sd_b * sd_b) / 2)
cohens_d = (mean_a - mean_b) / pooled_sd

print("Group A mean: " + str_string(mean_a))
print("Group B mean: " + str_string(mean_b))
print("Cohen's d: " + str_string(cohens_d))
```

---

## Group Operations

### Basic Grouping and Aggregation

```t
sales = read_csv("sales_data.csv")

-- Group by region, count rows (using $col = expr syntax)
by_region = sales
  |> group_by($region)
  |> summarize($count = nrow($region))

print(by_region)

-- Multiple aggregations
by_product = sales
  |> group_by($product)
  |> summarize($total_revenue = sum($revenue))
  
by_product = by_product
  |> mutate($avg_price = $total_revenue / $count)
```

### Grouped Statistics

```t
employees = read_csv("employees.csv")

-- Average salary by department
dept_stats = employees
  |> group_by($department)
  |> summarize($avg_salary = mean($salary))

-- Multiple groups
regional_dept_stats = employees
  |> group_by($region, $department)
  |> summarize($avg_salary = mean($salary))
  |> arrange($avg_salary, "desc")

print(regional_dept_stats)
```

### Grouped Mutations (Broadcast)

```t
-- Add department size to each row
employees_with_size = employees
  |> group_by($department)
  |> mutate($dept_size, \(g) nrow(g))

-- Add group mean to each row
employees_with_avg = employees
  |> group_by($department)
  |> mutate($dept_avg_salary, \(g) mean(g.salary, na_rm = true))
  
-- Calculate z-score within group
employees_normalized = employees_with_avg
  |> group_by($department)
  |> mutate($salary_z, \(g) 
      (g.salary - mean(g.salary, na_rm = true)) / sd(g.salary, na_rm = true)
    )
```

---

## Window Functions

### Ranking

```t
-- Load sales data
sales = read_csv("sales.csv")

-- Add row numbers
sales_ranked = sales
  |> mutate("row_num", \(row) row_number(sales.revenue))

-- Rank by revenue
sales_ranked = sales_ranked
  |> mutate("revenue_rank", \(row) min_rank(sales.revenue))
  |> arrange("revenue_rank")

-- Dense rank (no gaps)
sales_ranked = sales_ranked
  |> mutate("dense_revenue_rank", \(row) dense_rank(sales.revenue))

-- Percentiles
sales_ranked = sales_ranked
  |> mutate("percentile", \(row) percent_rank(sales.revenue))

print(sales_ranked)
```

### Offset Functions (lag/lead)

```t
-- Time series data
ts = read_csv("time_series.csv")

-- Previous value
ts_with_lag = ts
  |> mutate("prev_value", \(row) lag(ts.value))

-- Next value
ts_with_lead = ts
  |> mutate("next_value", \(row) lead(ts.value))

-- Calculate change
ts_with_change = ts_with_lag
  |> mutate("change", \(row) row.value - row.prev_value)

-- Multi-period lag
ts_with_lag2 = ts
  |> mutate("value_2_periods_ago", \(row) lag(ts.value, 2))
```

### Cumulative Functions

```t
-- Daily sales
daily = read_csv("daily_sales.csv")

-- Cumulative sum
daily_cumsum = daily
  |> mutate("cumulative_sales", \(row) cumsum(daily.sales))

-- Running average
daily_cumavg = daily
  |> mutate("running_avg", \(row) cummean(daily.sales))

-- Cumulative max
daily_cummax = daily
  |> mutate("peak_so_far", \(row) cummax(daily.sales))

-- Cumulative min
daily_cummin = daily
  |> mutate("lowest_so_far", \(row) cummin(daily.sales))

print(daily_cumsum)
```

---

## Reproducible Pipelines

### Data Analysis Pipeline

```t
intent {
  description: "Customer lifetime value analysis",
  assumes: "Data from 2023-01-01 to 2023-12-31",
  requires: "All monetary values in USD"
}

analysis = pipeline {
  -- Load raw data
  raw = read_csv("transactions.csv", clean_colnames = true)
  
  -- Clean data
  cleaned = raw
    |> filter(not is_na($amount) and $amount > 0)
    |> filter($date >= "2023-01-01" and $date <= "2023-12-31")
  
  -- Customer aggregations
  customer_stats = cleaned
    |> group_by($customer_id)
    |> summarize($total_spend = sum($amount))
    |> summarize($purchase_count = nrow($customer_id))
    |> mutate($avg_order_value = $total_spend / $purchase_count)
  
  -- Segment customers
  segments = customer_stats
    |> mutate($segment, \(row)
        if (row.total_spend > 1000) "high_value"
        else if (row.total_spend > 500) "medium_value"
        else "low_value"
      )
  
  -- Summary by segment
  segment_summary = segments
    |> group_by($segment)
    |> summarize($customer_count = nrow($segment), $avg_ltv = mean($total_spend))
    |> arrange($avg_ltv, "desc")
}

-- Access results
print(analysis.segment_summary)
write_csv(analysis.segments, "customer_segments.csv")
```

### Multi-Source Pipeline

```t
etl = pipeline {
  -- Load multiple sources
  sales = read_csv("sales.csv")
  customers = read_csv("customers.csv")
  products = read_csv("products.csv")
  
  -- Clean each source
  sales_clean = sales |> filter($amount > 0)
  
  -- Aggregate sales by customer
  customer_sales = sales_clean
    |> group_by($customer_id)
    |> summarize($total_sales = sum($amount))
  
  -- Combine with customer data (manual join via filter/map)
  -- (Assuming a join function exists or using manual matching)
  
  -- Final report
  report = customer_sales
    |> arrange($total_sales, "desc")
}

write_csv(etl.report, "sales_report.csv")
```

### Polyglot pipeline with a shell report

```t
analysis = pipeline {
  raw_data = node(
    command = read_csv("tests/pipeline/data/mtcars.csv", separator = "|"),
    runtime = T,
    serializer = t_write_csv,
    functions = "tests/pipeline/iolib.t"
  )

  summary_r = rn(
    command = <{ raw_data |> dplyr::group_by(cyl) |> dplyr::summarize(avg_mpg = mean(mpg)) }>,
    serializer = r_write_csv,
    deserializer = r_read_csv,
    functions = "tests/pipeline/iolib.R"
  )

  summary_py = pyn(
    command = <{ raw_data.groupby("cyl").agg({"mpg": "mean"}).reset_index().rename(columns={"mpg": "avg_mpg"}) }>,
    serializer = py_write_csv,
    deserializer = py_read_csv,
    functions = "tests/pipeline/iolib.py"
  )

  shell_report = shn(command = <{
#!/bin/sh
set -eu

# Dependencies for T's lexical pipeline analysis: raw_data summary_r summary_py
printf 'Polyglot summary report\n'
printf 'raw_data artifact: %s\n' "$T_NODE_raw_data/artifact"
printf '\nR summary\n'
cat "$T_NODE_summary_r/artifact"
printf '\nPython summary\n'
cat "$T_NODE_summary_py/artifact"
  }>)
}

build_pipeline(analysis)
```

This exact pattern is exercised end-to-end in `tests/pipeline/polyglot_shell_pipeline.t` and `.github/workflows/polyglot-shell-pipeline.yml`.

---

## Error Handling Patterns

### Defensive Programming

```t
-- Check for empty data
df = read_csv("data.csv")

safe_mean = if (nrow(df) == 0)
  error("ValueError", "Empty dataset")
else
  mean(df.value, na_rm = true)

-- Handle errors in pipeline
result = safe_mean ?|> \(x)
  if (is_error(x)) {
    print("Error: " + error_message(x))
    0.0  -- Default value
  } else {
    x
  }
```

### Validation Pipeline

```t
validate = pipeline {
  raw = read_csv("input.csv")
  
  -- Validation checks
  check_rows = if (nrow(raw) == 0)
    error("ValidationError", "No data found")
  else
    raw
  
  check_columns = if (ncol(check_rows) < 3)
    error("ValidationError", "Insufficient columns")
  else
    check_rows
  
  check_values = check_columns |> filter(
    not is_na($value) and $value > 0
  )
  
  -- If validation passes, proceed
  processed = if (nrow(check_values) > 100)
    check_values
  else
    error("ValidationError", "Too few valid rows")
}

-- Use maybe-pipe for error recovery
final = validate.processed ?|> \(x)
  if (is_error(x)) {
    print("Validation failed: " + error_message(x))
    -- Return empty placeholder or default
    NA
  } else {
    x
  }
```

### Graceful Degradation

```t
-- Try to load data, fall back if fails
data = read_csv("primary.csv") ?|> \(x)
  if (is_error(x)) {
    print("Primary source failed, trying backup...")
    read_csv("backup.csv")
  } else {
    x
  }

-- Chain multiple fallbacks
robust_load = read_csv("source1.csv")
  ?|> \(x) if (is_error(x)) read_csv("source2.csv") else x
  ?|> \(x) if (is_error(x)) read_csv("source3.csv") else x
  ?|> \(x) if (is_error(x)) error("AllSourcesFailed", "No data available") else x
```

---

## LLM Collaboration

### Intent-Driven Analysis

```t
intent {
  description: "Identify revenue drivers for Q4 2023",
  goal: "Determine which product categories drive revenue growth",
  assumes: "Complete sales data for Q4 2023",
  constraints: "Exclude returns and refunds",
  success_criteria: "R² > 0.7 for predictive model",
  stakeholder: "Product team"
}

-- Analysis follows intent
q4_sales = read_csv("q4_2023_sales.csv")

analysis = pipeline {
  clean = q4_sales
    |> filter($type != "return" and $type != "refund")
  
  by_category = clean
    |> group_by($category)
    |> summarize($total_revenue = sum($revenue))
    |> arrange($total_revenue, "desc")
  
  top_categories = by_category
    |> filter($total_revenue > 10000)
}

print(analysis.top_categories)
```

### Structured Collaboration

```t
intent {
  task: "customer_segmentation",
  description: "Segment customers by behavior for targeted marketing",
  
  inputs: {
    data_source: "customers.csv",
    date_range: "2023-01-01 to 2023-12-31",
    required_fields: ["customer_id", "purchase_frequency", "total_spend"]
  },
  
  methodology: "RFM analysis (Recency, Frequency, Monetary)",
  
  outputs: {
    segments: ["champions", "loyal", "at_risk", "churned"],
    format: "CSV with segment labels"
  },
  
  validation: {
    min_customers_per_segment: 50,
    total_customers_check: "should match input count"
  }
}

-- LLM generates implementation following intent structure
-- (This serves as a contract for regeneration)
```

### Audit Trail

```t
-- Intent blocks create audit trail for LLM-assisted work
intent {
  version: "1.0",
  author: "Data Team",
  llm_assistant: "GPT-4",
  created: "2024-01-15",
  last_modified: "2024-01-20",
  
  change_log: [
    {date: "2024-01-15", change: "Initial implementation"},
    {date: "2024-01-18", change: "Added NA handling"},
    {date: "2024-01-20", change: "Optimized grouping logic"}
  ],
  
  human_review: true,
  human_reviewer: "Alice Smith",
  review_date: "2024-01-21"
}

-- Rest of analysis...
```

---

## Complete Example: Sales Dashboard Data Prep

```t
-- Complete workflow: load, clean, analyze, export

intent {
  description: "Prepare sales data for dashboard",
  frequency: "Daily",
  outputs: ["summary_stats.csv", "top_products.csv", "regional_breakdown.csv"]
}

dashboard_prep = pipeline {
  -- 1. Load data
  raw_sales = read_csv("daily_sales.csv", clean_colnames = true)
  
  -- 2. Data quality
  clean_sales = raw_sales
    |> filter(not is_na($revenue) and $revenue > 0)
    |> filter(not is_na($product_id))
  
  -- 3. Summary statistics
  summary = {
    total_revenue: sum(clean_sales.revenue),
    total_orders: nrow(clean_sales),
    avg_order_value: mean(clean_sales.revenue),
    median_order: quantile(clean_sales.revenue, 0.5)
  }
  
  -- 4. Top products
  top_products = clean_sales
    |> group_by($product_name)
    |> summarize($revenue = sum($revenue))
    |> arrange($revenue, "desc")
  
  -- 5. Regional breakdown
  by_region = clean_sales
    |> group_by($region)
    |> summarize($revenue = sum($revenue), $orders = nrow($region))
    |> mutate($avg_order_value = $revenue / $orders)
    |> arrange($revenue, "desc")
}

-- Export results
write_csv(dashboard_prep.top_products, "top_products.csv")
write_csv(dashboard_prep.by_region, "regional_breakdown.csv")

print("Dashboard data prepared successfully")
print("Total revenue: " + str_string(dashboard_prep.summary.total_revenue))
```

---

---

## Next Steps

Now that you've seen T in action across various scenarios, explore the detailed guides and reference:

1. **[API Reference](api-reference.md)** — Exhaustive guide to T's standard library packages.
2. **[Data Manipulation Examples](data_manipulation_examples.md)** — More worked examples of data wrangling.
3. **[Pipeline Tutorial](pipeline_tutorial.md)** — Master T's reproducible computation model.
4. **[Package Development](package_development.md)** — Learn how to share your own T code.


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
- `coefficients`: Dictionary of term estimates
- `std_errors`: Dictionary of standard errors
- `r_squared`: R² statistic
- `adj_r_squared`: Adjusted R² statistic
- `sigma`: Residual standard error
- `nobs`: Number of observations
- `_tidy_df`: Tidy DataFrame of results

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
df = read_csv("sales.csv") |>
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

## Tiered AI Onboarding

T provides a structured way to onboard LLMs to new projects via the `t init` command. When a project is initialized, T generates two essential files that should be provided to the AI agent at the start of any conversation:

### 1. Project-Specific Guide (`AGENTS.md`)
This file tells the LLM exactly how the current project is structured and what the coding conventions are (e.g., "Nix is mandatory", "Use Arrow for data transfer"). It serves as the project's "rules of engagement" for AI assistants.

### 2. Tiered Language Reference (`T-LANGUAGE-REFERENCE.md`)
To handle different LLM context windows and project needs, T allows you to select a "Context Level" during initialization:

| Level | Description | Use Case |
| :--- | :--- | :--- |
| **small** | Core syntax and top 20 functions | Simple scripts, low-context models |
| **medium** | Exhaustive standard library index (Default) | General analysis and pipeline development |
| **full** | Comprehensive manual with detailed examples | Complex logic and package development |
| **huge** | Concatenated documentation of the entire ecosystem | Deep debugging and system-level tasks |

By providing these files, you ensure the LLM has the exact technical context needed to generate valid, idiomatic T code without trial-and-error.

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
Returns a tidy representation of coefficients. It returns a `Dict` where the tidy `DataFrame` is in `_tidy_df`.

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

> **PMML Trees & Boosting**: $T$ can now evaluate PMML-imported **Decision Trees**, **Random Forests**, and **XGBoost (GBTree)** models natively (no external runtime). This includes PMML exports from **scikit-learn** via `sklearn2pmml`. Use `read_pmml()` to load the model and `predict(df, model)` to score new data.

> **ONNX Native Inference**: $T$ can run ONNX models natively through ONNX Runtime using `read_onnx()` plus `predict(df, model)`. The current implementation supports single-input/single-output models and expects the selected numeric feature columns to match the model input width.

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
2. **Native T Loading**: Reading models with `read_onnx(path)` and scoring them with `predict(data, model)`.
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


# FILE: docs/nix-installation.md

# Installing Nix for T

T is a **reproducibility-first** language, and it achieves this by making the **Nix package manager** mandatory. Nix ensures that your T environment—including the compiler, libraries, and even your R or Python dependencies—remains consistent across machines and over time.

This guide explains how to install Nix on your system using the **Determinate Systems** installer, which we recommend for its ease of use and robust uninstallation capabilities.

## Introduction

Nix is a powerful package manager for Linux and macOS. While it might seem complex at first, its integration with T means you don't have to manage environments manually. T handles the "magic," but you need the "engine" (Nix) installed first.

## Recommended Installer: Determinate Systems

We recommend the [Determinate Systems Nix Installer](https://determinate.systems/posts/determinate-nix-installer) for all supported operating systems. It is modern, handles multi-user setups cleanly, and is easy to uninstall if needed.

### Installation Command

Open your terminal and run:

```bash
curl --proto '=https' --tlsv1.2 -sSf \
    -L https://install.determinate.systems/nix | \
     sh -s -- install
```

---

## Operating System Specific Notes

### Linux

The command above works on most modern Linux distributions (Ubuntu, Fedora, Debian, Arch, etc.).

> [!TIP]
> **Disk Space**: Nix stores everything in `/nix`. If your root partition is small, you might want to mount `/nix` on a larger partition.

### macOS

Nix on macOS is highly efficient but has some platform-specific nuances:

- **SDK Drift**: On macOS, Nix builds might occasionally depend on the macOS SDK from Xcode. While Nix handles this well, system updates sometimes cause "drift." If an older project stops building after a macOS update, try updating your T version or the project's nixpkgs pins.
- **Shared Libraries**: If you experience crashes related to "shared libraries," it might be due to your local R/Python user libraries interfering. T's `t init` command sets up guards to prevent this.

### Windows (WSL2)

Nix cannot run directly on Windows; it requires the **Windows Subsystem for Linux 2 (WSL2)**.

1. **Install WSL2**: Open PowerShell as Administrator and run:
   ```powershell
   wsl --install
   ```
2. **Enable systemd (Recommended)**: To support multi-user Nix in WSL2, we recommend enabling `systemd` in your Ubuntu/WSL2 shell:
   - Run `sudo nano /etc/wsl.conf`
   - Add the following:
     ```ini
     [boot]
     systemd=true
     ```
   - Save (Ctrl+O) and Exit (Ctrl+X).
   - In PowerShell, run `wsl --shutdown`, then relaunch your WSL2 terminal.
3. **Install Nix**: Run the Determinate Systems installation command inside your WSL2 terminal.

---

## Post-Installation: Enabling Flakes

T requires **Nix Flakes** to be enabled. The Determinate Systems installer usually enables these by default. You can verify by checking `~/.config/nix/nix.conf` or `/etc/nix/nix.conf`. It should contain:

```text
experimental-features = nix-command flakes
```

If it's missing, add it with:

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

---

## Binary Caches (Cachix)

To avoid building everything from source, we recommend configuring binary caches.

### Automatic Support in T Projects

When you initialize a T project (using `t init`), the generated `flake.nix` automatically includes the `rstats-on-nix` binary cache. This means that for project-specific operations, Nix will automatically attempt to fetch pre-built binaries.

### Global Configuration (Recommended)

To benefit from the binary cache even outside of T projects (e.g., when running `nix shell github:b-rodrigues/tlang`), you can configure the cache globally in your system's `nix.conf`:

```text
substituters = https://cache.nixos.org https://rstats-on-nix.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0=
```

> [!NOTE]
> If you used the Determinate Systems installer, you should add these to `/etc/nix/nix.conf`. You may need `sudo` to edit this file.

---

## Nix and Docker

Nix and Docker are often seen as alternatives, but they work exceptionally well together. While Docker manages container isolation, Nix handles the environment reproducibility *inside* or *for* those containers.

### 1. Using Nix Inside Docker

You might want to install Nix inside a Docker container for CI/CD pipelines (like GitHub Actions) or to serve applications with a strictly defined environment.

To install Nix inside a `Dockerfile` (e.g., using `ubuntu:latest` as a base), use the Determinate Systems installer with specific flags for container environments:

```dockerfile
FROM ubuntu:latest

RUN apt update && apt install -y curl

# Install Nix inside the container
RUN curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux \
  --extra-conf "sandbox = false" \
  --init none \
  --no-confirm

# Add Nix to the PATH
ENV PATH="${PATH}:/nix/var/nix/profiles/default/bin"
ENV user=root

# Optional: Configure the T binary cache
RUN mkdir -p /root/.config/nix && \
    echo "substituters = https://cache.nixos.org https://rstats-on-nix.cachix.org" > /root/.config/nix/nix.conf && \
    echo "trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0=" >> /root/.config/nix/nix.conf

CMD ["nix-shell"]
```

### 2. Building Docker Images with Nix

Instead of writing a `Dockerfile`, you can use Nix to **build** a Docker image. This is the ultimate way to achieve reproducibility, as Nix builds the entire image layer by layer from its own store, resulting in extremely lightweight and predictable images.

A simple Nix expression to build a T application image might look like this:

```nix
{ pkgs ? import <nixpkgs> {} }:

pkgs.dockerTools.buildImage {
  name = "t-analysis-app";
  tag = "latest";
  
  # Include T and any other required tools
  contents = [ pkgs.tlang pkgs.bashInteractive ];
  
  config = {
    Cmd = [ "t" "run" "scripts/pipeline.t" ];
    WorkingDir = "/my-project";
  };
}
```

You can build this image by running `nix-build docker.nix` and then load it into Docker with `docker load < result`.

---

## Troubleshooting

### "command not found: nix"
The installer usually updates your shell profile. Try restarting your terminal or running:
```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### Permission Denied
If you encounter permission issues when using Nix, ensure your user is in the `trusted-users` list in `/etc/nix/nix.conf`:
```text
trusted-users = root @wheel your_username
```

## Next Steps

Now that Nix is installed, you are ready to [Get Started with T](getting-started.md)!


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

### 1.1 AI Agent Onboarding (Optional)

When running `t init`, you will be prompted to select an **AI Agent Context Level**. This generates two essential files in your package root:

- **AGENTS.md**: A package-specific guide for AI assistants (and human collaborators).
- **T-LANGUAGE-REFERENCE.md**: A technical reference of the T language tailored to the requested depth (small, medium, full, or huge).

These files are designed to be read by LLMs (like Antigravity, Claude, or ChatGPT) at the start of a session to give them immediate, high-fidelity context about your package and the specific version of T you are using.

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
- **AGENTS.md**: Onboarding guide for AI Agents.
- **T-LANGUAGE-REFERENCE.md**: Tiered language reference for LLMs.

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


# FILE: docs/performance_analysis.md

# Performance Analysis

> Generated by `scripts/profile_performance.sh` — run the script to populate with actual measurements

---

## Test Environment

- **Date**: (run `scripts/profile_performance.sh` to populate)
- **Platform**: (auto-detected)
- **OCaml**: (auto-detected)

---

## Timing Results

### 10k Rows (100 groups)

| Operation | Time (s) |
|-----------|----------|
| Project 2 columns | — |
| Filter rows | — |
| Sum column | — |
| Group-by | — |
| Group aggregate (mean) | — |

### 100k Rows (1000 groups)

| Operation | Time (s) |
|-----------|----------|
| Project 2 columns | — |
| Sum column | — |
| Group-by | — |
| Group aggregate (sum) | — |
| sqrt (vectorized) | — |
| abs (vectorized) | — |
| compare scalar | — |

### 1M Rows (10000 groups)

| Operation | Time (s) |
|-----------|----------|
| Project 2 columns | — |
| Sum column | — |
| Mean column | — |
| Group-by | — |
| Group aggregate (mean) | — |

---

## Analysis

### Scaling Behavior

Operations should scale approximately linearly with row count:
- 10x rows → ~10x time for columnar operations
- Group-by scaling depends on group cardinality

### Hot Paths

The most time-critical operations for large datasets are:
1. **Group-by + aggregation**: Dominates pipeline execution time for grouped summarizations
2. **Filter**: Boolean mask construction + row extraction
3. **CSV reading**: I/O bound for large files; Arrow native reader provides significant speedup

### Optimization Opportunities

- **Materialization avoidance**: After `mutate()`, the native Arrow handle is dropped. Lazy evaluation could defer materialization.
- **Column pruning**: Pipelines that only use a subset of columns could skip loading unused columns from CSV.
- **Parallel execution**: Arrow Compute supports multi-threaded execution via Rayon; not yet exposed through FFI.

---

## Targets

See [docs/performance.md](performance.md) for detailed performance expectations and the Arrow backend architecture overview.


# FILE: docs/performance.md

# Performance

> Arrow backend architecture, vectorization strategy, and performance expectations

---

## Arrow Backend Architecture

T's DataFrame operations are backed by [Apache Arrow](https://arrow.apache.org/), a columnar memory format designed for efficient analytical processing. The Arrow integration provides:

- **Zero-copy column access**: Column views reference the underlying Arrow buffer directly, avoiding data copies when reading column data
- **Vectorized compute**: Arithmetic, math, and comparison operations use Arrow Compute kernels for SIMD-accelerated processing
- **Arrow-backed CSV results**: The public `read_csv()` builtin uses `Arrow_io.read_csv` on the default CSV path, preserving native Arrow handles when the native reader succeeds; non-default parsing options still use the richer OCaml fallback path
- **Hash-based grouping**: `group_by()` operations use Arrow's hash-based grouping when a native handle is present

> [!IMPORTANT]
> **Current beta improvement**: T now tries to keep DataFrames on the **native Arrow path** after supported structural changes by rebuilding a native Arrow table when the resulting schema is Arrow-builder-compatible. Primitive, dictionary/factor, date, datetime/timestamp, NA-only, and several list-column shapes can now stay native; users should still inspect the active backend explicitly for more complex nested schemas.

### Dual-Path Architecture

Every operation in T follows a **dual-path** pattern:

1. **Native Arrow path**: When the table has a `native_handle` (e.g., from `read_csv()`), operations delegate to Arrow Compute kernels via FFI for zero-copy, vectorized execution
2. **Pure OCaml fallback**: When no native handle is present (for example after a transformation that produces unsupported column builders), operations use pure OCaml implementations that work on typed columnar arrays

This ensures correctness regardless of backing storage, while maximizing performance when native Arrow buffers are available.

### How to Check Which Path a DataFrame Is On

Use `explain()` to inspect whether a DataFrame is still native-backed:

```t
df = read_csv("large.csv")
explain(df).storage_backend      -- "native_arrow" when the native handle is still active
explain(df).native_path_active   -- true

df2 = mutate(df, $ratio = $x / $y)
explain(df2).storage_backend     -- often still "native_arrow" for supported schemas
explain(df2).native_path_active  -- true when native backing was preserved

df3 = dataframe([[missing: NA], [missing: NA]])
explain(df3).storage_backend     -- "native_arrow" for NA-only schemas
explain(df3).native_path_active  -- true
```

This is the quickest way to understand whether a pipeline is still on the fast Arrow path or has already materialized into OCaml/T-managed arrays.

### Zero-Copy Column Views

The `Arrow_column` module provides `column_view` and `numeric_view` types that reference the backing Arrow table without copying data:

```
┌─────────────────────────────────────────────┐
│ Arrow Table (native memory)                 │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐    │
│  │ Column A │ │ Column B │ │ Column C │    │
│  │ (Float64)│ │ (Int64)  │ │ (String) │    │
│  └──────────┘ └──────────┘ └──────────┘    │
└─────────────────────────────────────────────┘
       ↑               ↑
  FloatView ba     IntView ba
  (Bigarray)       (Bigarray)
  (zero-copy)      (zero-copy)
```

For numeric columns (`Float64`, `Int64`), `zero_copy_view` returns a Bigarray that shares memory with the Arrow buffer — no allocation or copying occurs. The GC finalizer on the backing table ensures the Arrow memory remains valid.

---

## When Vectorization Is Used vs. Fallback

| Operation | Native Arrow Path | Pure OCaml Fallback |
|-----------|-------------------|---------------------|
| `select()` (project) | Zero-copy column selection | List-based column lookup |
| `filter()` | Arrow filter kernel with bool mask | Element-wise mask application |
| `arrange()` (sort) | Arrow sort kernel | Index-based reordering |
| `add_scalar`, `multiply_scalar`, etc. | Arrow Compute arithmetic kernels | Element-wise loop |
| `sqrt`, `abs`, `log`, `exp`, `pow` | Arrow Compute unary kernels | `Array.map` with stdlib math |
| `sum`, `mean`, `min`, `max` | Arrow Compute aggregation kernels | `Array.fold_left` |
| `compare` (eq, lt, gt, le, ge) | Arrow Compute comparison kernel | Element-wise comparison |
| `group_by` | Arrow hash-based grouping | Hashtable-based grouping |
| `group_aggregate` (sum, mean, count) | Arrow group aggregation kernels | Per-group fold |

**When does the fallback trigger?**

- When a transformation produces columns the current native Arrow builder path does not support
- When a table contains nested/list structures outside the currently supported shapes
- When the Arrow C GLib library is not available at build time

In practice, this means that workflows such as `read_csv() |> mutate(...) |> filter(...) |> summarize(...)` can now remain native for common primitive schemas and several richer Arrow-backed schemas, while more complex cases may still transition to the fallback path.

---

## Performance Expectations by Dataset Size

The following expectations assume standard hardware (modern x86-64, 8+ GB RAM) and typical datasets with 10–20 columns:

| Operation | 10k rows | 100k rows | 1M rows |
|-----------|----------|-----------|---------|
| Column selection (`select`) | <10ms | <50ms | <500ms |
| Row filtering (`filter`) | <10ms | <100ms | <1s |
| Arithmetic operations | <20ms | <200ms | <2s |
| Aggregation (`sum`, `mean`) | <5ms | <50ms | <500ms |
| Grouping + summarization | <50ms | <500ms | <5s |
| Window functions | <30ms | <300ms | <3s |
| CSV reading | <50ms | <200ms | <2s |

Performance scales approximately linearly with row count for columnar operations. Actual timings depend on hardware, dataset characteristics (column count, string lengths, group cardinality), and whether the native Arrow path is active.

---

## Known Performance Limitations

1. **Unsupported structural rebuilds still fall back**: T now attempts to rebuild native Arrow tables after structural changes, but some nested schemas still cannot be reconstructed through the current Arrow builder path. When that happens, subsequent operations run on the pure OCaml fallback path.

2. **Single-threaded execution**: All operations run on a single thread. Arrow's multi-threaded capabilities (Rayon-based parallelism) are not yet exposed through the FFI layer.

3. **String columns**: Zero-copy views are only available for numeric columns (`Float64`, `Int64`). String column operations always copy data into OCaml heap memory.

4. **Large group counts**: Group-by with very high cardinality (>10,000 unique groups) uses O(n × g) operations in the OCaml fallback path, where n is row count and g is group count.

5. **Memory usage**: Pure OCaml fallback stores data as `option array` (boxed), using more memory than Arrow's compact NAable representation. For 1M-row datasets, expect ~2× memory overhead compared to native Arrow storage.

---

## Roadmap: Post-Alpha Performance Improvements

The following optimizations are planned for future versions:

### Beta Performance Enhancements
- Expand native rebuild coverage further for more nested schemas so more structural transforms stay Arrow-backed
- Add richer `explain()` / developer diagnostics so backend transitions are obvious during pipeline development
- Multi-threaded Arrow operations using Rayon
- Lazy evaluation with query optimization
- Column pruning for pipelines (only load needed columns)
- Predicate pushdown for filtering
- Memory-mapped file support for datasets larger than RAM
- Streaming CSV reading for incremental processing

### Long-Term Performance Goals
- GPU acceleration via Arrow CUDA
- Distributed execution (Apache Spark/Dask-like)
- Advanced query optimization (cost-based optimizer)
- Native Parquet support (faster than CSV)
- Zero-copy interop with Python/Pandas via Arrow Flight


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


# FILE: docs/pipes.md

# The Pipe Operator (`|>`)

The pipe operator `|>` is the primary way to structure data-driven logic in T-Lang. It enables a clean, top-to-bottom flow that transforms data step-by-step.

## Philosophy: Monadic vs. Transparent

In T-Lang, errors are values, which raises a design question: *Should a pipe always pass the input along, even if it's an error?*

T-Lang implements the **Short-circuiting Pipe** by default.

### 1. Simple Forwarding (`|>`)
When using the standard pipe, T-Lang provides **Railway Oriented Programming** semantics.

- **If the input is Data**: It calls the function.
- **If the input is an Error**: It **short-circuits**. The function is never called, and the error is passed directly to the next stage.

```t
-- If read_csv fails, filter and select are never even attempted.
df = read_csv("missing.csv") 
  |> filter($age > 20)
  |> select($name)
-- Output: Error(FileError: "File not found")
```

**Why this design?**
1. **Reduce Noise**: It prevents a single failure from cascading into hundreds of confusing "Type Errors" downstream.
2. **Performance**: It avoids spinning up expensive resources (like JVMs or Python handlers) if the data flow is already broken.
3. **Happy Path**: It allows you to write the "Success Path" without littering your code with `if (is_error(x))` checks at every line.

### 2. Transparent Forwarding (`?|>`)
If you **want** to handle errors within the pipe (e.g., to log them or provide a default value), use the **Maybe-Pipe** `?|>`. This operator always forwards the value, even if it is an Error.

```t
read_csv("config.csv")
  ?|> \(v) if (is_error(v)) { default_config } else { v }
  |> validate_config()
```

## Function Calls vs. Pipes

It is important to note the difference between piping and direct function calls:

- **Function Calls `f(x)`**: Are **Transparent**. The function is always invoked with the argument. The function's internal logic then decides whether to propagate the error or handle it.
- **Pipe Stages `x |> f()`**: Are **Monadic**. The language engine intercepts the Error and skips the call entirely.

### Example
```t
e = error("stop")

-- Transparent call
is_error(e)   -- Returns true (the function runs)

-- Monadic pipe
e |> is_error() -- Returns Error("stop") (short-circuited, function never runs!)
```

## Summary
| Operator | Type | Error Behavior | Use Case |
| :--- | :--- | :--- | :--- |
| `|>` | Standard Pipe | **Short-circuit** | Normal data wrangling pipelines. |
| `?|>` | Maybe Pipe | **Transparent** | Error recovery, logging, and fallback logic. |
| `f(x)` | Function Call | **Transparent** | Builtin diagnostics and explicit error handling. |


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


# FILE: docs/pmml_tutorial.md

# PMML Tutorial

> A practical guide to moving classical models between R, Python, and T with `^pmml`

PMML is T's interchange format for many classical statistical and tree-based models.
It is useful when you want to:

- train a model in **R** or **Python**
- persist it as a stable artifact
- load it back into **T**
- score it natively with `predict(data, model)`

This tutorial focuses on the workflows that T supports today, including the initial
T-native `write_pmml()` pass-through path for PMML artifacts that were already loaded
from disk or a pipeline node.

---

## 1. When to Use PMML

Use `^pmml` when you want a model artifact that can cross runtime boundaries while still
being readable by T's native model tooling.

PMML is a good fit for:

- linear and GLM-style models exported from R
- scikit-learn models that `sklearn2pmml` can represent faithfully
- PMML tree and ensemble artifacts that T can score natively

PMML is **not** a universal model format. If your model family or preprocessing pipeline
cannot be represented faithfully in PMML, prefer `^onnx` or keep scoring in the source
runtime.

---

## 2. Prerequisites

PMML support is polyglot, so the exact requirements depend on where the model is produced
or consumed.

| Workflow | Main Requirements |
|---|---|
| R writes PMML | `r2pmml`, `XML`, `jsonlite`, `jre` |
| Python writes PMML | `sklearn2pmml` or `jpmml-statsmodels`, plus `jre` |
| Python reads PMML | JPMML evaluator via wrapper |
| T reads and scores PMML | built-in `read_pmml()` + native evaluator |

When PMML is used inside pipelines, these dependencies should be declared explicitly in
your project configuration so T can build the correct runtime environment.

---

## 3. Your First PMML Workflow

The simplest workflow is:

1. train in another runtime
2. serialize with `^pmml`
3. read the artifact in T
4. score it with `predict()`

```t
p = pipeline {
  model_r = rn(
    command = <{
      data <- read.csv("mtcars.csv")
      lm(mpg ~ wt + hp, data = data)
    }>,
    serializer = ^pmml
  )
}

build_pipeline(p)
model = read_node("model_r")
```

At this point `model` is a T model object reconstructed from the PMML artifact.

You can inspect it with the usual model helpers:

```t
summary(model)
fit_stats(model)
coef(model)
```

---

## 4. Scoring PMML Models Natively in T

Once a PMML model is in T, prediction looks the same as prediction for other supported
model objects:

```t
new_data = read_csv("mtcars_new.csv")
preds = predict(new_data, model)
```

This is the main attraction of PMML in T: training can happen in R or Python, but
downstream prediction, summary, and fit-stat extraction can stay inside the T runtime.

For PMML-imported tree models, random forests, and supported boosted ensembles, this is
already a strong workflow:

```t
forest = read_pmml("tests/golden/data/iris_random_forest.pmml")
iris = read_csv("tests/golden/data/iris.csv")
predict(iris, forest)
```

---

## 5. Training in R and Consuming in T

R is the most natural PMML producer for many classical models.

```t
p = pipeline {
  train_df = node(
    command = read_csv("mtcars.csv"),
    serializer = ^csv
  )

  model_r = rn(
    command = <{
      glm(am ~ wt + hp, data = train_df, family = binomial())
    }>,
    deserializer = ^csv,
    serializer = ^pmml
  )

  scored = node(
    command = predict(read_csv("mtcars.csv"), model_r),
    deserializer = ^pmml
  )
}
```

The important part is the boundary:

- the R node **writes** a PMML artifact with `serializer = ^pmml`
- the T node **reads** that artifact with `deserializer = ^pmml`

This keeps the interchange contract explicit.

---

## 6. Training in Python and Consuming in T

Python is a strong fit when your model is supported by `sklearn2pmml` or the JPMML
statsmodels bridge.

```t
p = pipeline {
  model_py = pyn(
    command = <{
      from sklearn.ensemble import RandomForestClassifier
      clf = RandomForestClassifier(random_state = 42)
      clf.fit(X, y)
      clf
    }>,
    serializer = ^pmml
  )

  scored = node(
    command = predict(read_csv("iris.csv"), model_py),
    deserializer = ^pmml
  )
}
```

As with R, the boundary is explicit:

- Python exports PMML
- T deserializes the PMML artifact
- T performs native scoring when the imported model family is supported

If the Python model cannot be represented faithfully in PMML, T should fail explicitly
rather than silently switching to a different interchange story.

---

## 7. Loading PMML Directly from Disk

You can also bypass pipelines and load an existing PMML file manually:

```t
model = read_pmml("model.pmml")
summary(model)
```

This is useful when:

- you already have exported PMML artifacts
- you want to inspect or score them interactively
- you want to compare several artifacts in the REPL

---

## 8. Writing PMML from T with `write_pmml()`

T now provides an initial native `write_pmml()` path, but it is intentionally narrow.

Today, `write_pmml()` supports **pass-through copying** of PMML artifacts that were
already loaded into T from:

- `read_pmml("path.pmml")`
- `read_node("node_name")` for PMML pipeline outputs

Example:

```t
model = read_pmml("model.pmml")
write_pmml(model, "model-copy.pmml")
```

This is useful when you want to:

- copy a PMML artifact to a deterministic location
- preserve a pipeline output outside the build cache
- re-materialize a model you inspected in the REPL

### Current Limitation

`write_pmml()` does **not** yet export arbitrary native T model objects to fresh PMML
XML. If you construct or fit a model natively in T and then call `write_pmml()`, T
should fail explicitly unless the value still carries an original PMML source artifact.

That is deliberate: T currently exposes a safe pass-through path, not a pretend PMML
writer for unsupported cases.

---

## 9. Recommended Workflow Pattern

For now, the safest PMML workflow is:

1. train in R or Python
2. export with `^pmml`
3. read and score in T
4. use `write_pmml()` only to preserve or copy existing PMML artifacts

In other words:

- use foreign runtimes as the **PMML producers**
- use T as the **PMML consumer and scorer**
- use `write_pmml()` as an **artifact-preservation tool**, not as a general exporter

---

## 10. Troubleshooting

### `read_node()` returns an error about missing PMML dependencies

Make sure the runtime that produced or reads the PMML artifact declares the required
packages in project configuration. PMML support is not implicit magic.

### Python PMML loading fails

Check that `jpmml-evaluator` is available in `[additional-tools]` and that `pyarrow` is available in `[py-dependencies]`. Also ensure the JVM-backed PMML toolchain is correctly provisioned.

### `write_pmml()` rejects a model

That usually means the value does not carry a source PMML artifact path. Reload it with
`read_pmml()` or obtain it from `read_node()` before calling `write_pmml()`.

### Predictions differ from the source runtime

Verify that the model family and preprocessing steps are truly representable in PMML.
The model coefficients are often not the problem; preprocessing fidelity usually is.

---

## 11. Next Steps

Now that you have a PMML workflow in place, continue with:

1. **[Statistical Models](models.md)** — inspect imported models with `summary()`, `fit_stats()`, and `predict()`.
2. **[Pipeline Tutorial](pipeline_tutorial.md)** — build larger multi-node workflows around PMML artifacts.
3. **[Serializers in T](serializers.md)** — understand how `^pmml`, `^onnx`, `^arrow`, and `^json` fit into the broader interchange system.


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

### 1.1 AI Agent Onboarding (Optional)

When running `t init`, you will be prompted to select an **AI Agent Context Level**. This generates two essential files in your project root:

- **AGENTS.md**: A project-specific guide for AI assistants (and human collaborators).
- **T-LANGUAGE-REFERENCE.md**: A technical reference of the T language tailored to the requested depth (small, medium, full, or huge).

These files are designed to be read by LLMs (like Antigravity, Claude, or ChatGPT) at the start of a session to give them immediate, high-fidelity context about your project and the specific version of T you are using.

This creates the following structure:

- **tproject.toml**: Project metadata and dependencies.
- **flake.nix**: Reproducible environment definition.
- **README.md**: Project documentation.
- **.gitignore**: Git exclusion list.
- **src/**: Your analysis scripts (e.g., `pipeline.t`).
- **data/**: Data files.
- **outputs/**: Output directory for results.
- **tests/**: Project-specific tests.
- **AGENTS.md**: Onboarding guide for AI Agents.
- **T-LANGUAGE-REFERENCE.md**: Tiered language reference for LLMs.

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
Upgrading project to T 0.51.4 and nixpkgs date 2026-03-21 (today's UTC date)...
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


# FILE: docs/reference/abs.md

# abs

Absolute value

Returns the absolute value of a number or vector/ndarray elements. Raises a TypeError if an NA value is encountered. Use `filter` or explicit missingness handling before calling `abs` on data that may contain NAs.

## Parameters

- **x** (`Number`): | Vector | NDArray The input value.

- **na_ignore** (`Bool`): Whether to preserve NA values in inputs. Default is false.


## Returns

| Vector | NDArray The absolute value.

## Examples

```t
abs(-5)
-- Returns = 5
```



# FILE: docs/reference/acosh.md

# acosh

Inverse hyperbolic cosine

Compute inverse hyperbolic cosine.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/acos.md

# acos

Inverse cosine

Compute arccosine.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/add_diagnostics.md

# add_diagnostics

Add Model Diagnostics

augments the data with model diagnostic columns (residuals, fitted values, etc.).

## Parameters

- **data** (`DataFrame`): (Optional) The data to augment.

- **model** (`Model`): The model object.


## Returns

The data with added diagnostic columns.

## Examples

```t
df = add_diagnostics(mtcars, model)
```

## See Also

[lm](lm.html)



# FILE: docs/reference/all_of.md

# all_of

Select an explicit set of columns

Selection helper that returns the supplied column names and errors if names are malformed.



# FILE: docs/reference/am.md

# am

Check whether a time is before noon

Returns true for Date values and for Datetime values whose hour is earlier than 12.



# FILE: docs/reference/anova.md

# anova

Analysis of Variance (ANOVA)

Compares nested models using F-tests (for linear models) or Chi-square tests (for GLMs).

## Parameters

- **...** (`Model`): One or more model objects to compare.


## Returns

ANOVA table with statistics and p-values.

## Examples

```t
m1 = lm(mpg ~ wt, data = mtcars)
m2 = lm(mpg ~ wt + hp, data = mtcars)
anova(m1, m2)
```



# FILE: docs/reference/anti_join.md

# anti_join

Filter rows lacking matches

Keeps rows from the left DataFrame that do not have a matching key in the right DataFrame.



# FILE: docs/reference/any_of.md

# any_of

Select columns that exist

Selection helper that keeps the supplied column names when they are present.



# FILE: docs/reference/apropos.md

# apropos

Search for functions by keyword

Searches all documented functions for names or descriptions matching the query.

## Parameters

- **query** (`String`): The keyword to search for.


## Returns



## Examples

```t
apropos("stat")
-- Finds functions like "fit_stats", "mean", "sd", etc.
```

## See Also

[help](help.html)



# FILE: docs/reference/args.md

# args

Get function arguments and their types

Returns a dictionary where keys are parameter names and values are their types. Supports both user-defined lambdas and builtin functions.

## Parameters

- **fn** (`Function`): The function to inspect.


## Returns

A dictionary of name = Type.

## Examples

```t
args(sqrt)
-- Returns: {x = "Number | Vector | NDArray"}

f = \(x = Int, y = Float -> Int) x + y
args(f)
-- Returns: {x: "Int", y = "Float"}
```



# FILE: docs/reference/arrange.md

# arrange

Arrange rows

Sorts a DataFrame by a column. Use "desc" for descending order.

## Parameters

- **df** (`DataFrame`): The input DataFrame.

- **col** (`Symbol`): The column to sort by.

- **direction** (`String`): (Optional) "asc" (default) or "desc".


## Returns

The sorted DataFrame.

## Examples

```t
arrange(mtcars, $mpg)
arrange(mtcars, $mpg, "desc")
```

## See Also

[group_by](group_by.html), [filter](filter.html)



# FILE: docs/reference/arrange_node.md

# arrange_node

Arrange Pipeline Nodes

Returns a new pipeline with nodes sorted by a metadata field. Execution order is always determined by the DAG — this affects only the order in which nodes appear when printing or serializing the pipeline.

## Parameters

- **p** (`Pipeline`): The pipeline to sort.

- **field** (`Symbol`): The metadata field to sort by (e.g. `$depth`, `$name`).

- **direction** (`String`): (Optional) `"asc"` (default) or `"desc"`.


## Returns

A new pipeline with nodes reordered.

## Examples

```t
p |> arrange_node($depth)
p |> arrange_node($name, "asc")
p |> arrange_node($depth, "desc")
```

## See Also

[select_node](select_node.html), [filter_node](filter_node.html)



# FILE: docs/reference/as_date.md

# as_date

Convert values to Date

Converts strings, datetimes, and related temporal values to Date values.



# FILE: docs/reference/as_datetime.md

# as_datetime

Convert values to Datetime

Converts strings, dates, and related temporal values to Datetime values.



# FILE: docs/reference/as_factor.md

# as_factor

Coerce values to factors

Alias for factor() that converts values to factor-encoded vectors.



# FILE: docs/reference/asinh.md

# asinh

Inverse hyperbolic sine

Compute inverse hyperbolic sine.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/asin.md

# asin

Inverse sine

Compute arcsine.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/assert.md

# assert

Assert Condition

Checks if a condition is true, raising an error if false.

## Parameters

- **condition** (`Bool`): The condition to check.

- **message** (`String`): (Optional) Custom error message.


## Returns

True if successful.

## Examples

```t
assert(1 == 1)
assert(x > 0, "x must be positive")
```

## See Also

[is_error](is_error.html), [error](error.html)



# FILE: docs/reference/atan2.md

# atan2

Two-argument arctangent

Compute `atan2(y, x)` with quadrant-aware angle.

## Parameters

- **y** (`Number`): | List | Vector | NDArray Y coordinate(s).

- **x** (`Number`): Scalar X coordinate.


## Returns

| Vector | NDArray Computed result (scalar or vectorized).



# FILE: docs/reference/atanh.md

# atanh

Inverse hyperbolic tangent

Compute inverse hyperbolic tangent.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/atan.md

# atan

Inverse tangent

Compute arctangent.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/augment.md

# augment

Augment Data with Model Calculations

Appends model predictions, residuals, and potentially diagnostic metrics to a dataset.

## Parameters

- **data** (`DataFrame`): The dataset to augment.

- **model** (`Model`): The model object.


## Returns

The original DataFrame with appended `fitted`, `resid`, etc.

## Examples

```t
aug = augment(mtcars, model)
```



# FILE: docs/reference/bind_cols.md

# bind_cols

Combine DataFrames by columns

Combines columns from multiple DataFrames side by side.



# FILE: docs/reference/bind_rows.md

# bind_rows

Stack DataFrames by rows

Appends rows from multiple DataFrames into a single DataFrame.



# FILE: docs/reference/body.md

# body

Get function body

Returns the implementation body of a function. For T functions, it returns the body as an Expr object. For built-ins, it returns metadata about the OCaml implementation.

## Parameters

- **fn** (`Function`): The function to inspect.


## Returns

| String The function body or implementation info.

## Examples

```t
f = \(x) (x + 1)
body(f)
```



# FILE: docs/reference/build_pipeline_internal.md

# build_pipeline_internal

Build Pipeline Internally

Calls `nix-build` on the generated `pipeline.nix` file. Extracts the store path of the result and saves a build log with an exact mapping of node names to artifact paths in the Nix store.

## Parameters

- **p** (`PipelineResult`): The pipeline AST structure.


## Returns

The output Nix store path or an error string.



# FILE: docs/reference/build_pipeline.md

# build_pipeline

Build Pipeline Artifacts

Builds a pipeline to `pipeline.nix` and records node artifacts in a local registry.

## Parameters

- **p** (`Pipeline`): The pipeline to build.

- **verbose** (`Int`): (Optional) Nix build verbosity level. `0` keeps build failures quiet; values above `0` print failed node logs.


## Returns

The output path (Nix store path or local fallback directory).

## See Also

[read_node](read_node.html)



# FILE: docs/reference/case_when.md

# case_when

Vectorized Case-When

Evaluates multiple conditions and returns the corresponding value for the first true condition. Similar to SQL's CASE WHEN. Conditions are provided as formulas `condition ~ value`.

## Parameters

- **.default** (`Any`): (Optional) Default value if no condition is met.

- **...** (`Formula`): Conditions and their corresponding return values.


## Returns

A vector of the resulting values.



# FILE: docs/reference/casewhen.md

# casewhen

Vectorized case-when

Evaluates a series of `condition ~ value` formulas sequentially. Returns the value corresponding to the first true condition for each element.

## Parameters

- **...** (`Formula`): One or more formulas of the form `condition ~ value`.

- **.default** (`Any`): (Optional) Value to return if no condition matches. Defaults to NA.


## Returns

A vector of the matched values.

## Examples

```t
casewhen(
x > 0 ~ "Positive",
x < 0 ~ "Negative",
.default = "Zero"
)
```



# FILE: docs/reference/cat.md

# cat

Print values without escaping

Prints one or more values to stdout using a custom separator. Unlike print(), it does not add a trailing newline and supports custom separators. Strings are printed raw (with escape sequences like \n interpreted).

## Parameters

- **...** (`Any`): Values to print.

- **sep** (`String`): = " " Separator between values.


## Returns



## Examples

```t
cat("Line 1", "Line 2", sep = "\n")
```



# FILE: docs/reference/cbind.md

# cbind

Column bind matrices

HELPER: Combines two matrices by columns.

## Parameters

- **a** (`NDArray`): First matrix.

- **b** (`NDArray`): Second matrix.


## Returns

The combined matrix.



# FILE: docs/reference/ceiling_date.md

# ceiling_date

Round dates up

Rounds Date or Datetime values up to the requested unit boundary.



# FILE: docs/reference/ceiling.md

# ceiling

Ceiling function

Return smallest integer greater than or equal to input.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/ceil.md

# ceil

Ceiling alias

Alias for `ceiling`.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/chain.md

# chain

Chain Two Pipelines

Connects two pipelines by merging them. The second pipeline can reference node names from the first pipeline as dependencies — these are automatically satisfied. Errors if there are name collisions (other than the intentional inter-pipeline wiring) or if no shared names exist between the two pipelines.

## Parameters

- **p1** (`Pipeline`): The upstream pipeline (provides outputs).

- **p2** (`Pipeline`): The downstream pipeline (consumes inputs).


## Returns

A merged pipeline with p2's nodes wired to p1's outputs.

## Examples

```t
p_etl |> chain(p_model)
```

## See Also

[union](union.html), [parallel](parallel.html)



# FILE: docs/reference/char_at.md

# char_at

Get character at index

Returns a single-character string at the specified index.

## Parameters

- **s** (`String`): The input string.

- **i** (`Int`): The index (0-based).


## Returns

The character at the index.



# FILE: docs/reference/clean_colnames.md

# clean_colnames

Clean DataFrame Column Names

Standardizes column names using a snake_case convention. Removes special characters and handles duplicates.

## Parameters

- **x** (`DataFrame`): | List[String] The object with names to clean.


## Returns

| List[String] The object with cleaned names.

## See Also

[colnames](colnames.html)



# FILE: docs/reference/clean_names.md

# clean_names

Clean Column Names

Normalizes a list of strings to be safe, consistent column names. Converts symbols (like €) to text, strips diacritics, lowers the case, replaces non-alphanumeric characters with underscores, and resolves duplicates.

## Parameters

- **names** (`Vector[String]`): The column names to clean.


## Returns

The cleaned column names.



# FILE: docs/reference/coef.md

# coef

Model Coefficients

Extracts the coefficient estimates from a model object, keyed by term name.

## Parameters

- **model** (`Model`): The model object (e.g., from lm() or imported).


## Returns

Coefficient estimates with columns `term` and `estimate`.

## Examples

```t
coef(model)
```

## See Also

[conf_int](conf_int.html), [summary](summary.html)



# FILE: docs/reference/col_lens.md

# col_lens

Create a Column Lens

Targets a column in a DataFrame or a key in a Dictionary.

## Parameters

- **name** (`String`): The column or key name.


## Returns

A lens for the specified column/key.



# FILE: docs/reference/colnames.md

# colnames

Get column names

Returns a list of column names in the DataFrame.

## Parameters

- **df** (`DataFrame`): The input DataFrame.


## Returns

The column names.

## Examples

```t
colnames(mtcars)
```

## See Also

[nrow](nrow.html), [ncol](ncol.html)



# FILE: docs/reference/compare.md

# compare

Compare Models

Align multiple model coefficient tables into a single wide DataFrame for comparison.

## Parameters

- **...** (`Variadic`): Models or a List of models to compare.


## Returns

A wide DataFrame with aligned terms and suffixed columns.

## Examples

```t
m1 = lm(mpg ~ wt, data = mtcars)
m2 = lm(mpg ~ wt + hp, data = mtcars)
compare(m1, m2)
```



# FILE: docs/reference/complete.md

# complete

Complete a data frame

Turns implicit missing values into explicit missing values. Supports nesting() to restrict combinations to those present in the data.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **...** (`Symbol`): | Call Variable number of column names (use $col syntax) or nesting(...) calls.

- **fill** (`Dict`): (Optional) A dictionary supplying a single value to use instead of NA for missing combinations.

- **explicit** (`Bool`): (Optional) Should both implicit and explicit missing values be filled? (Default: true)


## Returns

The completed DataFrame.

## Examples

```t
complete(df, $group, $item_id, $item_name)
complete(df, $group, nesting($item_id, $item_name))
```



# FILE: docs/reference/compose.md

# compose

Compose Lenses

Combines two lenses into one, focusing on a value deep within a nested structure.

## Parameters

- **lens1** (`Lens`): The outer lens.

- **lens2** (`Lens`): The inner lens.


## Returns

The composite lens.



# FILE: docs/reference/conf_int.md

# conf_int

Confidence Intervals for Model Coefficients

Computes confidence intervals for model coefficients based on the Student's t distribution.

## Parameters

- **model** (`Model`): The model object (e.g., from lm() or imported).

- **level** (`Float`): Confidence level (default 0.95).


## Returns

Columns = `term`, `lower`, `upper`.

## Examples

```t
conf_int(model)
conf_int(model, 0.99)
```

## See Also

[summary](summary.html), [coef](coef.html)



# FILE: docs/reference/contains.md

# contains

Check if string contains substring

Returns true if `sub` is present in `s`.

## Parameters

- **s** (`String`): The search string.

- **sub** (`String`): The substring to find.


## Returns

True if found, false otherwise.



# FILE: docs/reference/cor.md

# cor

Correlation

Computes the Pearson correlation coefficient between two vectors.

## Parameters

- **x** (`Vector`): | List First numeric vector.

- **y** (`Vector`): | List Second numeric vector.

- **na_rm** (`Bool`): (Optional) Should missing values be removed? Default is false.


## Returns

The correlation coefficient (-1 to 1).

## Examples

```t
cor(mtcars["mpg"], mtcars["wt"])
```



# FILE: docs/reference/cosh.md

# cosh

Hyperbolic cosine

Compute hyperbolic cosine.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/cos.md

# cos

Cosine

Compute cosine (radians).

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/count.md

# count

Count rows by group

Counts rows in a DataFrame, optionally by selected columns or existing group keys.



# FILE: docs/reference/cov.md

# cov

Covariance

Compute sample covariance of two numeric vectors.

## Parameters

- **x** (`Vector`): | List First numeric input.

- **y** (`Vector`): | List Second numeric input.

- **na_rm** (`Bool`): = false Pairwise remove NA values.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/crossing.md

# crossing

Create a data frame from all combinations of inputs

crossing() generates all unique combinations of its inputs. Unlike expand_grid(), it de-duplicates and sorts its inputs.

## Parameters

- **...** (`Vector`): | List Named or unnamed inputs to combine.


## Returns

A DataFrame with all unique combinations.

## Examples

```t
crossing(x = 1:3, y = ["a", "b"])
```



# FILE: docs/reference/cumall.md

# cumall

Cumulative All

Calculates the cumulative logical AND of a vector.

## Parameters

- **x** (`Vector`): The input boolean vector.


## Returns

The cumulative AND.

## Examples

```t
cumall([true, true, false, true])
-- Returns = [true, true, false, false]
```

## See Also

[cumany](cumany.html)



# FILE: docs/reference/cumany.md

# cumany

Cumulative Any

Calculates the cumulative logical OR of a vector.

## Parameters

- **x** (`Vector`): The input boolean vector.


## Returns

The cumulative OR.

## Examples

```t
cumany([false, false, true, false])
-- Returns = [false, false, true, true]
```

## See Also

[cumall](cumall.html)



# FILE: docs/reference/cume_dist.md

# cume_dist

Cumulative Distribution

Calculates the cumulative distribution function (proportion of values <= current).

## Parameters

- **x** (`Vector`): The input vector.


## Returns

The cumulative distribution (0 to 1).

## See Also

[percent_rank](percent_rank.html)



# FILE: docs/reference/cummax.md

# cummax

Cumulative Maximum

Calculates the cumulative maximum of a vector.

## Parameters

- **x** (`Vector`): The input numeric vector.


## Returns

The cumulative maximum.

## Examples

```t
cummax([1, 3, 2, 4])
-- Returns = [1, 3, 3, 4]
```

## See Also

[cumsum](cumsum.html), [cummin](cummin.html), [max](max.html)



# FILE: docs/reference/cummean.md

# cummean

Cumulative Mean

Calculates the cumulative mean of a vector.

## Parameters

- **x** (`Vector`): The input numeric vector.

- **na_rm** (`Bool`): = false Remove NA values before computation.


## Returns

The cumulative mean.

## Examples

```t
cummean([1, 2, 3])
-- Returns = [1.0, 1.5, 2.0]

cummean([1, NA, 3], na_rm = true)
-- Returns = [1.0, 1.0, 2.0]
```

## See Also

[cumsum](cumsum.html), [mean](mean.html)



# FILE: docs/reference/cummin.md

# cummin

Cumulative Minimum

Calculates the cumulative minimum of a vector.

## Parameters

- **x** (`Vector`): The input numeric vector.


## Returns

The cumulative minimum.

## Examples

```t
cummin([3, 2, 4, 1])
-- Returns = [3, 2, 2, 1]
```

## See Also

[cumsum](cumsum.html), [cummax](cummax.html), [min](min.html)



# FILE: docs/reference/cumsum.md

# cumsum

Cumulative Sum

Calculates the cumulative sum of a vector.

## Parameters

- **x** (`Vector`): The input numeric vector.


## Returns

The cumulative sum.

## Examples

```t
cumsum([1, 2, 3])
-- Returns = [1, 3, 6]
```

## See Also

[cummin](cummin.html), [cummax](cummax.html), [sum](sum.html)



# FILE: docs/reference/cut.md

# cut

Discretize numeric vector

Splits a numeric vector into intervals.

## Parameters

- **x** (`Vector[Number]`): | List[Number] The vector to discretize.

- **breaks** (`Int`): | Vector[Number] Number of bins or specific cut points.


## Returns

Vector of interval labels.

## Examples

```t
cut([1, 2, 3, 4, 5], 2)
cut([1, 2, 3, 4, 5], [0, 2.5, 5])
```



# FILE: docs/reference/cv.md

# cv

Coefficient of variation

Compute sample sd divided by mean.

## Parameters

- **x** (`Vector`): | List Numeric input.

- **na_rm** (`Bool`): = false Remove NA values first.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/dataframe.md

# dataframe

Create a DataFrame

Constructs a DataFrame from either a list of rows (Dicts) or a Dictionary of columns (Vectors/Lists).

## Parameters

- **data** (`List[Dict]|Dict`): The data rows or columns.


## Returns

The created DataFrame.

## Examples

```t
# Row-wise construction:
df = dataframe([
{"a": 1, "b": 2},
{"a": 3, "b": 4}
])

# Column-wise construction (supported for VDict):
df2 = dataframe([a: [1, 3], b = [2, 4]])

# Scalar values are recycled to match other column lengths:
df3 = dataframe([x: [1, 2, 3], constant = 0])
```

## See Also

[read_csv](read_csv.html)



# FILE: docs/reference/day.md

# day

Extract the day of month

Returns the day-of-month component from Date or Datetime values.



# FILE: docs/reference/days_in_month.md

# days_in_month

Get the number of days in a month

Returns the number of days in the month described by a date, datetime, or explicit year/month pair.



# FILE: docs/reference/dense_rank.md

# dense_rank

Dense Rank

Assigns ranks to unique values, with no gaps.

## Parameters

- **x** (`Vector`): The input vector.


## Returns

The ranks.

## Examples

```t
dense_rank([1, 2, 2, 4])
-- Returns = [1, 2, 2, 3]
```

## See Also

[min_rank](min_rank.html)



# FILE: docs/reference/deserialize_from_file.md

# deserialize_from_file

Binary Deserialization

Reads a serialized T value from a file. Verifies an integrity digest before unmarshalling to reject tampered or externally-supplied artifacts.  SECURITY NOTE: OCaml Marshal is not safe for fully untrusted input. The MD5 digest check detects accidental corruption only — MD5 is not cryptographically secure and provides no protection against intentional tampering. Only load .tobj files produced by your own T installation.

## Parameters

- **path** (`String`): Source file path.


## Returns

String] Value or error.



# FILE: docs/reference/deserialize.md

# deserialize

Deserialize Value

Deserializes a value from a `.tobj` file.

## Parameters

- **path** (`String`): Input file path.


## Returns



## See Also

[serialize](serialize.html)



# FILE: docs/reference/df_residual.md

# df_residual

Residual Degrees of Freedom

Returns the residual degrees of freedom of a model.

## Parameters

- **model** (`Model`): The model object.


## Returns

The residual degrees of freedom.

## Examples

```t
model = lm(mpg ~ wt, data = mtcars)
df = df_residual(model)
```



# FILE: docs/reference/diag.md

# diag

Create or extract diagonal

If input is 1D, creates a diagonal matrix. If input is 2D, extracts the diagonal elements.

## Parameters

- **x** (`NDArray`): The input array.


## Returns

The diagonal matrix or vector.

## See Also

[matmul](matmul.html)



# FILE: docs/reference/difference.md

# difference

Subtract one pipeline from another

Returns the nodes that appear in the first pipeline but not the second.



# FILE: docs/reference/dir_exists.md

# dir_exists

Check if directory exists

Checks if a directory exists at the given path.

## Parameters

- **path** (`String`): The path to check.


## Returns

True if it's a directory.

## Examples

```t
dir_exists("tests")
```



# FILE: docs/reference/dispersion.md

# dispersion

Dispersion Parameter

Returns the dispersion parameter of a Generalized Linear Model (GLM). For linear models (lm), use `sigma()` instead.

## Parameters

- **model** (`Model`): The model object.


## Returns

The dispersion parameter.

## Examples

```t
model = glm(survived ~ age, data = df, family = "binomial")
d = dispersion(model)
```

## See Also

[sigma](sigma.html)



# FILE: docs/reference/distinct.md

# distinct

Keep unique rows

Returns the distinct rows of a DataFrame, optionally using selected columns as uniqueness keys.



# FILE: docs/reference/downstream_of.md

# downstream_of

Extract Downstream Subgraph

Returns a new pipeline containing the named node and all nodes that transitively depend on it (descendants in the DAG).

## Parameters

- **p** (`Pipeline`): The pipeline.

- **name** (`String`): The name of the target node.


## Returns

A new pipeline with only the node and its descendants.

## Examples

```t
p |> downstream_of("data")
```

## See Also

[subgraph](subgraph.html), [upstream_of](upstream_of.html)



# FILE: docs/reference/drop_na.md

# drop_na

Remove rows with missing values

drop_na() removes rows from a DataFrame where specified columns have missing values.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **...** (`Symbol`): (Optional) Columns to check for missing values (use $col syntax).


## Returns

The DataFrame with NA rows removed.

## Examples

```t
drop_na(df)
drop_na(df, $age, $score)
```



# FILE: docs/reference/ends_with.md

# ends_with

Check if string ends with suffix

Returns true if `s` ends with the specified `suffix`.

## Parameters

- **s** (`String`): The string to check.

- **suffix** (`String`): The suffix to look for.


## Returns

True if s ends with suffix.



# FILE: docs/reference/enquo.md

# enquo

Capture a function argument's expression (non-standard evaluation)

Must be called inside a function body. Captures the unevaluated expression that the caller passed as the named parameter, returning it as an Expr. Accepts exactly one argument: a bare symbol naming one of the function's parameters.

## Parameters

- **param** (`Symbol`): The name of the parameter whose expression to capture.


## Returns

The captured expression object.

## Examples

```t
my_select = \(df = DataFrame, col = Any -> DataFrame) {
col_expr = enquo(col)
eval(expr(df |> select(!!col_expr)))
}
my_select(iris, $Sepal.Length)
```



# FILE: docs/reference/enquos.md

# enquos

Capture variadic argument expressions (non-standard evaluation)

Must be called inside a function body. Captures the unevaluated expressions passed through the variadic `...` parameter as a named List of Expr values. Call with `...` or with no arguments.

## Parameters

- **...** (`Any`): The variadic parameter to capture.


## Returns

A list of captured expressions, preserving argument names.

## Examples

```t
my_summarize = \(df = DataFrame, ... -> DataFrame) {
cols = enquos(...)
eval(expr(df |> summarize(!!!cols)))
}
my_summarize(iris, mean_sep = mean($Sepal.Length))
```



# FILE: docs/reference/env.md

# env

Get environment variable

Retrieves the value of an environment variable.

## Parameters

- **name** (`String`): The name of the environment variable.


## Returns

| NA The value of the variable, or null if not set.

## Examples

```t
env("HOME")
```



# FILE: docs/reference/env_var_lens.md

# env_var_lens

Pipeline Env Var Lens

Targets a specific environment variable for a node in a Pipeline.

## Parameters

- **node_name** (`String`): The name of the node.

- **var_name** (`String`): The name of the environment variable.


## Returns

A lens for the environment variable.



# FILE: docs/reference/error_code.md

# error_code

Get error code

Returns the error code as a string (e.g., "TypeError", "ValueError").

## Parameters

- **x** (`Error`): The error value to inspect.


## Returns

The error code as a string.



# FILE: docs/reference/error_context.md

# error_context

Get error context

Returns a dictionary containing contextual information about where and why the error occurred.

## Parameters

- **x** (`Error`): The error value to inspect.


## Returns

A dictionary of related context data.



# FILE: docs/reference/error.md

# error

Raise Error

Raises a runtime error with a message and optional code.

## Parameters

- **message** (`String`): The error message.

- **code** (`String`): (Optional) Error code (e.g., "ValueError").


## Returns



## Examples

```t
error("Invalid input")
error("ValueError", "Must be positive")
```

## See Also

[is_error](is_error.html), [assert](assert.html)



# FILE: docs/reference/error_message.md

# error_message

Get error message

Returns the human-readable message associated with an error.

## Parameters

- **x** (`Error`): The error value to inspect.


## Returns

The error message.



# FILE: docs/reference/eval.md

# eval

Evaluate a quoted expression or quosure

Evaluates an Expression in the current environment, or a Quosure in its captured lexical environment. Returns plain values unchanged.



# FILE: docs/reference/everything.md

# everything

Select every column

Selection helper that returns every column name from a DataFrame.



# FILE: docs/reference/exit.md

# exit

Exit the interpreter

Terminates the current T process and accepts an optional numeric exit status.



# FILE: docs/reference/expand.md

# expand

Create all combinations of values

Generates all unique combinations of the provided columns or expressions. Supports nesting() to only include combinations present in the data.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **...** (`Symbol`): | Vector | Call Specification of columns to expand.


## Returns

A DataFrame with all combinations.

## Examples

```t
expand(df, $type, $size)
expand(df, nesting($type, $size))
expand(df, $type, 2010:2012)
```



# FILE: docs/reference/explain_json.md

# explain_json

Explain Value as JSON

Returns a JSON string representation of the explain output.

## Parameters

- **x** (`Any`): The value to explain.


## Returns

The JSON description.

## See Also

[explain](explain.html)



# FILE: docs/reference/explain.md

# explain

Explain Value

Returns a dictionary describing the structure and content of a value.

When the input is a pipeline node result (for example from `read_node(...)`),
the returned dictionary separates node/container metadata from the explained
payload via a `contents` field.

In the REPL and in `t explain ...`, this dictionary is rendered with a
tree-style CLI view for readability. Programmatically, it is still an ordinary
`Dict`.

## Parameters

- **x** (`Any`): The value to explain.


## Returns

A structured description of the value.

## Examples

```t
explain(mtcars)
explain(1)
node_info = explain(read_node("model"))
node_info.contents
```

## See Also

[str](str.html), [type](type.html)


# FILE: docs/reference/exp.md

# exp

Exponential function

Calculates e raised to the power of x.

## Parameters

- **x** (`Number`): | Vector | NDArray The input value.

- **na_ignore** (`Bool`): Whether to preserve NA values in inputs. Default is false.


## Returns

| Vector | NDArray The exponential.

## Examples

```t
exp(1)
-- Returns = 2.71828...
```

## See Also

[pow](pow.html), [log](log.html)



# FILE: docs/reference/expr.md

# expr

Capture an expression

Captures the provided expression as an Expr object without evaluating it. Useful for metaprogramming, quotation, and custom evaluation.

## Parameters

- **x** (`Any`): The expression to capture.


## Returns

The captured expression object.

## Examples

```t
e = expr(1 + 2)
eval(e)
```



# FILE: docs/reference/exprs.md

# exprs

## Parameters

- **...** (`Any`): One or more expressions to capture.


## Returns

A list of captured expressions.

## Examples

```t
exprs(1 + 1, x = 2 * 2)
```



# FILE: docs/reference/factor.md

# factor

Create factor values

Converts values to factor-encoded vectors with derived or explicit levels.



# FILE: docs/reference/fct_c.md

# fct_c

Concatenate factor vectors

Combines multiple factor vectors while reconciling their levels.



# FILE: docs/reference/fct_collapse.md

# fct_collapse

Collapse multiple levels

Merges several existing factor levels into new grouped levels.



# FILE: docs/reference/fct_drop.md

# fct_drop

Drop unused factor levels

Removes levels that are not referenced by any value in the factor vector.



# FILE: docs/reference/fct_expand.md

# fct_expand

Add explicit factor levels

Adds extra levels to a factor without changing existing assignments.



# FILE: docs/reference/fct_infreq.md

# fct_infreq

Order factor levels by frequency

Reorders factor levels so that more frequent levels appear first.



# FILE: docs/reference/fct_lump_min.md

# fct_lump_min

Lump factor levels below a minimum count

Collapses factor levels whose counts fall below a minimum threshold.



# FILE: docs/reference/fct_lump_n.md

# fct_lump_n

Keep the most frequent factor levels

Collapses infrequent factor levels into an other bucket while keeping the most frequent levels.



# FILE: docs/reference/fct_lump_prop.md

# fct_lump_prop

Lump factor levels below a minimum proportion

Collapses factor levels whose frequency falls below a proportion threshold.



# FILE: docs/reference/fct.md

# fct

Create factors in first-seen order

Creates a factor whose levels follow the first appearance order of the input values.



# FILE: docs/reference/fct_other.md

# fct_other

Replace unlisted levels with Other

Keeps selected factor levels and maps the rest to an other bucket.



# FILE: docs/reference/fct_recode.md

# fct_recode

Rename factor levels

Recodes existing factor levels using named replacements.



# FILE: docs/reference/fct_relevel.md

# fct_relevel

Move selected levels to the front

Explicitly reorders a factor by moving named levels ahead of the remaining levels.



# FILE: docs/reference/fct_reorder.md

# fct_reorder

Order factor levels by another vector

Reorders factor levels using summary statistics computed from a companion numeric vector.



# FILE: docs/reference/fct_rev.md

# fct_rev

Reverse factor levels

Reverses the order of the levels in a factor vector.



# FILE: docs/reference/file_exists.md

# file_exists

Check if file exists

Checks if a regular file exists at the given path. Returns false if the path is a directory or does not exist.

## Parameters

- **path** (`String`): The path to check.


## Returns

True if it's a regular file.

## Examples

```t
file_exists("data.csv")
```



# FILE: docs/reference/fill.md

# fill

Fill missing values

Fills missing values in selected columns using the next or previous entry.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **...** (`Symbol`): Columns to fill (use $col syntax).

- **.direction** (`String`): (Optional) Direction in which to fill missing values.


## Returns

The filled DataFrame.

## Examples

```t
fill(df, $category, .direction = "down")
```



# FILE: docs/reference/filter_lens.md

# filter_lens

Filter Lens

Targets elements in a List/Vector or rows in a DataFrame that satisfy a predicate.

## Parameters

- **p** (`Function`): The predicate function.


## Returns

A lens for elements matching the predicate.



# FILE: docs/reference/filter.md

# filter

Filter rows

Retains rows that satisfy the predicate function.

## Parameters

- **df** (`DataFrame`): The input DataFrame.

- **predicate** (`Function`): A function returning Bool for each row.


## Returns

The filtered DataFrame.

## Examples

```t
filter(mtcars, \(row) -> row.mpg > 20)
```

## See Also

[arrange](arrange.html), [select](select.html)



# FILE: docs/reference/filter_node.md

# filter_node

Filter Pipeline Nodes

Returns a new pipeline containing only the nodes for which the predicate returns `true`. Uses NSE (`$field`) to refer to node metadata fields.  No DAG validity check is performed. If a retained node depends on a node that was removed, that inconsistency surfaces only at `build_pipeline` or `pipeline_run`.  Supported metadata fields: `$name`, `$runtime`, `$serializer`, `$deserializer`, `$noop`, `$depth`, `$command_type`.

## Parameters

- **p** (`Pipeline`): The pipeline to filter.

- **predicate** (`Function`): A predicate function returning Bool for each node.


## Returns

A new pipeline with only the matching nodes.

## Examples

```t
p |> filter_node($runtime == "python")
p |> filter_node($noop == false)
p |> filter_node($depth <= 2)
```

## See Also

[rename_node](rename_node.html), [select_node](select_node.html), [mutate_node](mutate_node.html)



# FILE: docs/reference/fit_stats.md

# fit_stats

Model Goodness-of-Fit Statistics

Returns a tidy DataFrame of model-level statistics (e.g. R-squared, AIC, BIC). Supports single model objects or labeled collections of models for comparison.  When passed a list or dictionary of models, it stacks the results into a single DataFrame, automatically adding a 'model' column if labels are present.

## Parameters

- **x** (`Model`): | List[Model] | Dict[String, Model] The model(s) to inspect.


## Returns

A tidy one-row-per-model summary of goodness-of-fit.

## Examples

```t
m1 = lm(mpg ~ wt, data = mtcars)
fit_stats(m1)
m2 = lm(mpg ~ hp + wt, data = mtcars)
fit_stats([Model_1: m1, Model_2 = m2])
```

## See Also

[summary](summary.html), [lm](lm.html)



# FILE: docs/reference/fivenum.md

# fivenum

Five-number summary

Return min, Q1, median, Q3, max.

## Parameters

- **x** (`Vector`): | List Numeric input.

- **na_rm** (`Bool`): = false Remove NA values first.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/floor_date.md

# floor_date

Round dates down

Rounds Date or Datetime values down to the requested unit boundary.



# FILE: docs/reference/floor.md

# floor

Floor function

Return greatest integer less than or equal to input.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/force_tz.md

# force_tz

Retag a datetime with a timezone

Reinterprets local clock components under a new timezone label.



# FILE: docs/reference/format_date.md

# format_date

Format dates as strings

Formats Date values with a user-supplied format string.



# FILE: docs/reference/format_datetime.md

# format_datetime

Format datetimes as strings

Formats Datetime values with a user-supplied format string.



# FILE: docs/reference/full_join.md

# full_join

Join all rows from both tables

Joins two DataFrames and keeps rows appearing in either input.



# FILE: docs/reference/get.md

# get

Unified data retrieval for names, collections, pipelines, and lenses

`get()` is a polymorphic retrieval helper:

- `get("x")` / `get(sym("x"))` looks up a variable in the current environment
- `get(collection, index)` indexes a `List`, `Vector`, or `NDArray`
- `get(pipeline, "node")` retrieves a pipeline node result
- `get(data, lens)` applies a lens focus to a value
- `get(node_lens("name"))` retrieves a sandboxed sibling-node artifact via `T_NODE_<name>`

## Parameters

- **target** (`String | Symbol | List | Vector | NDArray | Pipeline | Lens`): The value or name to retrieve from.

- **selector** (`Int | String | Symbol | Lens`, optional): The index, node name, or lens to apply when a second argument is provided.


## Returns

The looked-up value, selected element, node result, or lens focus.

## Examples

```t
salary = 50000
get("salary")                  -- 50000
get(sym("salary"))             -- 50000

get([10, 20, 30], 1)           -- 20

p = pipeline { a = 1 }
get(p, "a")                    -- 1

l = col_lens("mpg")
get(mtcars, l)                 -- focused column

get(node_lens("model"))        -- sandbox artifact lookup
```


# FILE: docs/reference/getwd.md

# getwd

Get current working directory

Returns the absolute path of the current working directory.

## Returns

The current working directory.

## Examples

```t
getwd()
```



# FILE: docs/reference/glimpse.md

# glimpse

Glimpse DataFrame

Prints a summary of the DataFrame structure, including dimensions, column names, types, and first few values.

## Parameters

- **df** (`DataFrame`): The input DataFrame.


## Returns



## Examples

```t
glimpse(mtcars)
```

## See Also

[str](str.html), [colnames](colnames.html)



# FILE: docs/reference/greet.md

# greet

Greet someone

A placeholder function that returns a friendly greeting.

## Parameters

- **name** (`String`): The name of the person to greet.


## Returns

A greeting message.

## Examples

```t
greet("world")
-- Returns: "Hello, world!"

```



# FILE: docs/reference/group_by.md

# group_by

Group by columns

Groups a DataFrame by one or more columns for subsequent aggregation.

## Parameters

- **df** (`DataFrame`): The input DataFrame.

- **...** (`Symbol`): Variable number of grouping columns.


## Returns

The grouped DataFrame.

## Examples

```t
group_by(mtcars, $cyl)
group_by(mtcars, $cyl, $gear)
```

## See Also

[ungroup](ungroup.html), [summarize](summarize.html)



# FILE: docs/reference/head.md

# head

Get the first n rows/items

Returns the first n items from a List, Vector, or DataFrame. For DataFrames, it returns the top n rows.

## Parameters

- **data** (`DataFrame`): | List | Vector The collection to slice.

- **n** (`Int`): = 5 Number of items to return.


## Returns

| List | Vector A subset of the input containing the first n items.

## Examples

```t
head([1, 2, 3, 4, 5, 6], n = 3)
-- Returns = [1, 2, 3]

df |> head(n = 10)
```



# FILE: docs/reference/help.md

# help

Display documentation for a function

Prints the help documentation for the specified function, including signature, parameters, return value, and examples.

## Parameters

- **name** (`String`): | Symbol The name of the function to document.


## Returns



## Examples

```t
help("mean")
help(print)
```

## See Also

[apropos](apropos.html)



# FILE: docs/reference/hour.md

# hour

Extract the hour

Returns the hour component from Datetime values.



# FILE: docs/reference/huber_loss.md

# huber_loss

Huber loss

Compute Huber loss for residuals and positive delta.

## Parameters

- **x** (`Number`): | Vector | List Residual value(s).

- **delta** (`Number`): Positive threshold.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/identical.md

# identical

Deep Equality Check

Checks if two objects are structurally identical, including nested elements and metadata. Unlike `==`, this works for all types, including collections (Lists, Vectors, DataFrames).

## Parameters

- **a** (`Any`): First object to compare.

- **b** (`Any`): Second object to compare.


## Returns

true if identical, false otherwise.



# FILE: docs/reference/idx_lens.md

# idx_lens

Index Lens

Targets an element in a List or Vector by its 0-based index.

## Parameters

- **i** (`Int`): The index to target.


## Returns

A lens for the specified index.



# FILE: docs/reference/ifelse.md

# ifelse

Vectorized If-Else

Evaluates a condition and returns values from `true_val` or `false_val` depending on the condition. Supports missing value handling via the `missing` argument.

## Parameters

- **condition** (`Vector[Bool]`): The logical condition to evaluate.

- **true_val** (`Any`): Expected return value when condition is true.

- **false_val** (`Any`): Expected return value when condition is false.

- **missing** (`Any`): (Optional) Value to return when condition is NA.

- **out_type** (`String`): (Optional) Explicit output type casting.


## Returns

A vector of the resulting values.

## Examples

```t
ifelse([true, false, NA], "Yes", "No", missing = "Unknown")
```



# FILE: docs/reference/index.md

# Function Reference

| Function | Description |
| --- | --- |
| [%within%](%25within%25.html) | Test interval membership |
| [abs](abs.html) | Absolute value |
| [acos](acos.html) | Inverse cosine |
| [acosh](acosh.html) | Inverse hyperbolic cosine |
| [add_diagnostics](add_diagnostics.html) | Add Model Diagnostics |
| [all_of](all_of.html) | Select an explicit set of columns |
| [am](am.html) | Check whether a time is before noon |
| [anova](anova.html) | Analysis of Variance (ANOVA) |
| [anti_join](anti_join.html) | Filter rows lacking matches |
| [any_of](any_of.html) | Select columns that exist |
| [apropos](apropos.html) | Search for functions by keyword |
| [args](args.html) | Get function arguments and their types |
| [arrange](arrange.html) | Arrange rows |
| [arrange_node](arrange_node.html) | Arrange Pipeline Nodes |
| [as_date](as_date.html) | Convert values to Date |
| [as_datetime](as_datetime.html) | Convert values to Datetime |
| [as_factor](as_factor.html) | Coerce values to factors |
| [asin](asin.html) | Inverse sine |
| [asinh](asinh.html) | Inverse hyperbolic sine |
| [assert](assert.html) | Assert Condition |
| [atan](atan.html) | Inverse tangent |
| [atan2](atan2.html) | Two-argument arctangent |
| [atanh](atanh.html) | Inverse hyperbolic tangent |
| [augment](augment.html) | Augment Data with Model Calculations |
| [bind_cols](bind_cols.html) | Combine DataFrames by columns |
| [bind_rows](bind_rows.html) | Stack DataFrames by rows |
| [body](body.html) | Get function body |
| [build_pipeline](build_pipeline.html) | Build Pipeline Artifacts |
| [build_pipeline_internal](build_pipeline_internal.html) | Build Pipeline Internally |
| [case_when](case_when.html) | Vectorized Case-When |
| [casewhen](casewhen.html) | Vectorized case-when |
| [cat](cat.html) | Print values without escaping |
| [cbind](cbind.html) | Column bind matrices |
| [ceil](ceil.html) | Ceiling alias |
| [ceiling](ceiling.html) | Ceiling function |
| [ceiling_date](ceiling_date.html) | Round dates up |
| [chain](chain.html) | Chain Two Pipelines |
| [char_at](char_at.html) | Get character at index |
| [clean_colnames](clean_colnames.html) | Clean DataFrame Column Names |
| [coef](coef.html) | Model Coefficients |
| [col_lens](col_lens.html) | Create a Column Lens |
| [colnames](colnames.html) | Get column names |
| [compare](compare.html) | Compare Models |
| [complete](complete.html) | Complete a data frame |
| [compose](compose.html) | Compose Lenses |
| [conf_int](conf_int.html) | Confidence Intervals for Model Coefficients |
| [contains](contains.html) | Check if string contains substring |
| [cor](cor.html) | Correlation |
| [cos](cos.html) | Cosine |
| [cosh](cosh.html) | Hyperbolic cosine |
| [count](count.html) | Count rows by group |
| [cov](cov.html) | Covariance |
| [crossing](crossing.html) | Create a data frame from all combinations of inputs |
| [cumall](cumall.html) | Cumulative All |
| [cumany](cumany.html) | Cumulative Any |
| [cume_dist](cume_dist.html) | Cumulative Distribution |
| [cummax](cummax.html) | Cumulative Maximum |
| [cummean](cummean.html) | Cumulative Mean |
| [cummin](cummin.html) | Cumulative Minimum |
| [cumsum](cumsum.html) | Cumulative Sum |
| [cut](cut.html) | Discretize numeric vector |
| [cv](cv.html) | Coefficient of variation |
| [dataframe](dataframe.html) | Create a DataFrame |
| [day](day.html) | Extract the day of month |
| [days_in_month](days_in_month.html) | Get the number of days in a month |
| [dense_rank](dense_rank.html) | Dense Rank |
| [deserialize](deserialize.html) | Deserialize Value |
| [df_residual](df_residual.html) | Residual Degrees of Freedom |
| [diag](diag.html) | Create or extract diagonal |
| [difference](difference.html) | Subtract one pipeline from another |
| [dir_exists](dir_exists.html) | Check if directory exists |
| [dispersion](dispersion.html) | Dispersion Parameter |
| [distinct](distinct.html) | Keep unique rows |
| [downstream_of](downstream_of.html) | Extract Downstream Subgraph |
| [drop_na](drop_na.html) | Remove rows with missing values |
| [ends_with](ends_with.html) | Check if string ends with suffix |
| [enquo](enquo.html) | Capture a function argument's expression (non-standard evaluation) |
| [enquos](enquos.html) | Capture variadic argument expressions (non-standard evaluation) |
| [env](env.html) | Get environment variable |
| [env_var_lens](env_var_lens.html) | Pipeline Env Var Lens |
| [error](error.html) | Raise Error |
| [error_code](error_code.html) | Get error code |
| [error_context](error_context.html) | Get error context |
| [error_message](error_message.html) | Get error message |
| [eval](eval.html) | Evaluate a quoted expression or quosure |
| [everything](everything.html) | Select every column |
| [exit](exit.html) | Exit the interpreter |
| [exp](exp.html) | Exponential function |
| [expand](expand.html) | Create all combinations of values |
| [explain](explain.html) | Explain Value |
| [explain_json](explain_json.html) | Explain Value as JSON |
| [expr](expr.html) | Capture an expression |
| [exprs](exprs.html) |  |
| [factor](factor.html) | Create factor values |
| [fct](fct.html) | Create factors in first-seen order |
| [fct_c](fct_c.html) | Concatenate factor vectors |
| [fct_collapse](fct_collapse.html) | Collapse multiple levels |
| [fct_drop](fct_drop.html) | Drop unused factor levels |
| [fct_expand](fct_expand.html) | Add explicit factor levels |
| [fct_infreq](fct_infreq.html) | Order factor levels by frequency |
| [fct_lump_min](fct_lump_min.html) | Lump factor levels below a minimum count |
| [fct_lump_n](fct_lump_n.html) | Keep the most frequent factor levels |
| [fct_lump_prop](fct_lump_prop.html) | Lump factor levels below a minimum proportion |
| [fct_other](fct_other.html) | Replace unlisted levels with Other |
| [fct_recode](fct_recode.html) | Rename factor levels |
| [fct_relevel](fct_relevel.html) | Move selected levels to the front |
| [fct_reorder](fct_reorder.html) | Order factor levels by another vector |
| [fct_rev](fct_rev.html) | Reverse factor levels |
| [file_exists](file_exists.html) | Check if file exists |
| [fill](fill.html) | Fill missing values |
| [filter](filter.html) | Filter rows |
| [filter_lens](filter_lens.html) | Filter Lens |
| [filter_node](filter_node.html) | Filter Pipeline Nodes |
| [fit_stats](fit_stats.html) | Model Goodness-of-Fit Statistics |
| [fivenum](fivenum.html) | Five-number summary |
| [floor](floor.html) | Floor function |
| [floor_date](floor_date.html) | Round dates down |
| [force_tz](force_tz.html) | Retag a datetime with a timezone |
| [format_date](format_date.html) | Format dates as strings |
| [format_datetime](format_datetime.html) | Format datetimes as strings |
| [full_join](full_join.html) | Join all rows from both tables |
| [get](get.html) | Get Value via Lens |
| [getwd](getwd.html) | Get current working directory |
| [glimpse](glimpse.html) | Glimpse DataFrame |
| [greet](greet.html) | Greet someone |
| [group_by](group_by.html) | Group by columns |
| [head](head.html) | Get the first n rows/items |
| [help](help.html) | Display documentation for a function |
| [hour](hour.html) | Extract the hour |
| [huber_loss](huber_loss.html) | Huber loss |
| [idx_lens](idx_lens.html) | Index Lens |
| [ifelse](ifelse.html) | Vectorized If-Else |
| [index_of](index_of.html) | Find index of substring |
| [inner_join](inner_join.html) | Join matching rows |
| [inspect_node](inspect_node.html) | Inspect Pipeline Node Metadata |
| [inspect_pipeline](inspect_pipeline.html) | Inspect Pipeline Logs |
| [intent_fields](intent_fields.html) | Get All Intent Fields |
| [intent_get](intent_get.html) | Get Intent Field |
| [intersect](intersect.html) | Keep shared pipeline nodes |
| [interval](interval.html) | Create an interval |
| [inv](inv.html) | Matrix inverse |
| [iota](iota.html) | Create a vector of ones |
| [iqr](iqr.html) | Interquartile range |
| [is_character](is_character.html) | Check for character columns |
| [is_empty](is_empty.html) | Check if string is empty |
| [is_error](is_error.html) | Check if a value is an Error |
| [is_factor](is_factor.html) | Check for factor columns |
| [is_leap_year](is_leap_year.html) | Check for leap years |
| [is_logical](is_logical.html) | Check for logical columns |
| [is_na](is_na.html) | Check for NA |
| [is_numeric](is_numeric.html) | Check for numeric columns |
| [isoweek](isoweek.html) | Extract the ISO week number |
| [isoyear](isoyear.html) | Extract the ISO week-based year |
| [kron](kron.html) | Kronecker product |
| [kurtosis](kurtosis.html) | Excess kurtosis |
| [lag](lag.html) | Lag values |
| [last_index_of](last_index_of.html) | Find last index of substring |
| [lead](lead.html) | Lead values |
| [left_join](left_join.html) | Join rows from the left table |
| [length](length.html) | Get length |
| [lens](lens.html) | Lens Library |
| [levels](levels.html) | Get factor levels |
| [list_files](list_files.html) | List files in directory |
| [list_logs](list_logs.html) | List Pipeline Logs |
| [lm](lm.html) | Linear Model |
| [log](log.html) | Natural logarithm |
| [mad](mad.html) | Median absolute deviation |
| [make_date](make_date.html) | Construct a Date value |
| [make_datetime](make_datetime.html) | Construct a Datetime value |
| [make_period](make_period.html) | Create a period value |
| [map](map.html) | Map a function over a list |
| [matches](matches.html) | Match columns by regex |
| [matmul](matmul.html) | Matrix multiplication |
| [max](max.html) | Maximum value |
| [mday](mday.html) | Extract the day of month |
| [mean](mean.html) | Compute arithmetic mean of numeric values |
| [median](median.html) | Median |
| [min](min.html) | Minimum value |
| [min_rank](min_rank.html) | Minimum Rank |
| [minute](minute.html) | Extract the minute |
| [mode](mode.html) | Mode |
| [modify](modify.html) | Multiple Lens Transformations |
| [month](month.html) | Extract or label the month |
| [mutate](mutate.html) | Mutate DataFrame |
| [mutate_node](mutate_node.html) | Mutate Pipeline Node Metadata |
| [n](n.html) | Group size aggregation |
| [n_distinct](n_distinct.html) | Count distinct values |
| [na](na.html) | Generic NA |
| [na_bool](na_bool.html) | Boolean NA |
| [na_float](na_float.html) | Float NA |
| [na_int](na_int.html) | Integer NA |
| [na_string](na_string.html) | String NA |
| [ncol](ncol.html) | Number of columns |
| [ndarray](ndarray.html) | Create an N-dimensional array |
| [ndarray_data](ndarray_data.html) | Get NDArray data |
| [nest](nest.html) | Nest columns into sub-dataframes |
| [nesting](nesting.html) | Helper to find combinations present in data |
| [nobs](nobs.html) | Number of Observations |
| [node](node.html) | Configure a Pipeline Node |
| [node_lens](node_lens.html) | Pipeline Node Lens |
| [normalize](normalize.html) | Normalize values |
| [now](now.html) | Get the current datetime |
| [nrow](nrow.html) | Number of rows |
| [ntile](ntile.html) | N-tiles |
| [ordered](ordered.html) | Create ordered factors |
| [over](over.html) | Transform Focused Value |
| [package_info](package_info.html) | Get package information |
| [packages](packages.html) | List available packages |
| [parallel](parallel.html) | Combine Pipelines in Parallel |
| [parse_date](parse_date.html) | Parse dates from strings |
| [parse_datetime](parse_datetime.html) | Parse datetimes from strings |
| [parse_file](parse_file.html) | Parse T-Doc Comments |
| [patch](patch.html) | Overlay one pipeline onto another |
| [path_abs](path_abs.html) | Resolve relative path to absolute |
| [path_basename](path_basename.html) | Get filename component of a path |
| [path_dirname](path_dirname.html) | Get directory portion of a path |
| [path_ext](path_ext.html) | Get file extension |
| [path_join](path_join.html) | Join multiple path segments |
| [path_stem](path_stem.html) | Get filename without extension |
| [pchisq](pchisq.html) | Chi-squared distribution CDF |
| [percent_rank](percent_rank.html) | Percent Rank |
| [pf](pf.html) | F distribution CDF |
| [pipeline_assert](pipeline_assert.html) | Assert Pipeline Validity |
| [pipeline_copy](pipeline_copy.html) | Copy Pipeline Node Artifacts to Local Directory |
| [pipeline_cycles](pipeline_cycles.html) | Detect Pipeline Cycles |
| [pipeline_deps](pipeline_deps.html) | List Node Dependencies |
| [pipeline_depth](pipeline_depth.html) | Maximum Topological Depth |
| [pipeline_dot](pipeline_dot.html) | Export Pipeline as DOT Graph |
| [pipeline_edges](pipeline_edges.html) | Pipeline Dependency Edges |
| [pipeline_leaves](pipeline_leaves.html) | Pipeline Leaf Nodes |
| [pipeline_node](pipeline_node.html) | Get Pipeline Node |
| [pipeline_nodes](pipeline_nodes.html) | List Pipeline Nodes |
| [pipeline_print](pipeline_print.html) | Pretty-Print a Pipeline |
| [pipeline_roots](pipeline_roots.html) | Pipeline Root Nodes |
| [pipeline_run](pipeline_run.html) | Run Pipeline |
| [pipeline_summary](pipeline_summary.html) | Pipeline Summary |
| [pipeline_to_frame](pipeline_to_frame.html) | Convert Pipeline to DataFrame |
| [pipeline_validate](pipeline_validate.html) | Validate a Pipeline |
| [pivot_longer](pivot_longer.html) | Pivot longer |
| [pivot_wider](pivot_wider.html) | Pivot wider |
| [pm](pm.html) | Check whether a time is after noon |
| [pnorm](pnorm.html) | Normal distribution CDF |
| [poly](poly.html) | Polynomial basis expansion |
| [populate_pipeline](populate_pipeline.html) | Populate Pipeline |
| [pow](pow.html) | Power function |
| [predict](predict.html) | Linear Model Prediction |
| [pretty_print](pretty_print.html) | Pretty-print a value |
| [print](print.html) | Print values to standard output |
| [prune](prune.html) | Prune Pipeline Leaf Nodes |
| [pt](pt.html) | Student t distribution CDF |
| [pull](pull.html) | Extract column as vector |
| [pyn](pyn.html) | Configure a Python Pipeline Node |
| [qn](qn.html) | Configure a Quarto Pipeline Node |
| [quantile](quantile.html) | Quantiles |
| [quarter](quarter.html) | Extract the quarter |
| [quo](quo.html) | Capture an expression with its lexical environment (quosure) |
| [quos](quos.html) | Capture multiple expressions with their lexical environment (quosures) |
| [range](range.html) | Range |
| [read_arrow](read_arrow.html) | Read Arrow IPC file |
| [read_csv](read_csv.html) | Read CSV file |
| [read_file](read_file.html) | Read file contents |
| [read_log](read_log.html) | Read Node Build Log |
| [read_node](read_node.html) | Read Pipeline Node Artifact |
| [read_parquet](read_parquet.html) | Read Parquet file |
| [rebuild_node](rebuild_node.html) | Rebuild a Pipeline Node |
| [relocate](relocate.html) | Move columns to a new position |
| [rename](rename.html) | Rename DataFrame columns |
| [rename_node](rename_node.html) | Rename a Pipeline Node |
| [replace_first](replace_first.html) | Replace first occurrence |
| [replace_na](replace_na.html) | Replace missing values |
| [reshape](reshape.html) | Reshape an NDArray |
| [residuals](residuals.html) | Model Residuals |
| [rewire](rewire.html) | Rewire a Node's Dependencies |
| [rm](rm.html) | Remove objects from the environment |
| [rn](rn.html) | Configure an R Pipeline Node |
| [round](round.html) | Round values |
| [round_date](round_date.html) | Round dates to the nearest unit |
| [row_lens](row_lens.html) | Row Lens |
| [row_number](row_number.html) | Row Number |
| [run](run.html) | Run a shell command |
| [run_doctor](run_doctor.html) | Run Package/Project Doctor |
| [scaffold_package](scaffold_package.html) | Scaffold a new T package |
| [scaffold_project](scaffold_project.html) | Scaffold a new T project |
| [scale](scale.html) | Scale values |
| [score](score.html) | Model Scoring |
| [sd](sd.html) | Standard Deviation |
| [second](second.html) | Extract the second |
| [select](select.html) | Select columns |
| [select_node](select_node.html) | Select Node Metadata Fields |
| [semester](semester.html) | Extract the semester |
| [semi_join](semi_join.html) | Filter rows using matches in another table |
| [separate](separate.html) | Separate a character column into multiple columns |
| [separate_rows](separate_rows.html) | Split delimited values into rows |
| [seq](seq.html) | Generate a sequence of integers |
| [serialize](serialize.html) | Serialize Value |
| [set](set.html) | Set Focused Value |
| [shape](shape.html) | Get NDArray dimensions |
| [shn](shn.html) | Configure a Shell Pipeline Node |
| [sigma](sigma.html) | Residual Standard Deviation |
| [sign](sign.html) | Sign of number |
| [signif](signif.html) | Significant-digit rounding |
| [sin](sin.html) | Sine |
| [sinh](sinh.html) | Hyperbolic sine |
| [skewness](skewness.html) | Skewness |
| [slice](slice.html) | Extract slice |
| [slice_max](slice_max.html) | Keep rows with the largest values |
| [slice_min](slice_min.html) | Keep rows with the smallest values |
| [source](source.html) | Get function source code |
| [sqrt](sqrt.html) | Square root |
| [standardize](standardize.html) | Standardize values |
| [starts_with](starts_with.html) | Check if string starts with prefix |
| [str_count](str_count.html) | Count regex matches |
| [str_detect](str_detect.html) | Test whether a regex matches |
| [str_extract](str_extract.html) | Extract the first regex match |
| [str_extract_all](str_extract_all.html) | Extract all regex matches |
| [str_flatten](str_flatten.html) | Flatten a collection of strings |
| [str_format](str_format.html) | Named string interpolation |
| [str_join](str_join.html) | Join strings with a separator |
| [str_lines](str_lines.html) | Split string into lines |
| [str_nchar](str_nchar.html) | Get character count |
| [str_pad](str_pad.html) | Pad strings to a target width |
| [str_repeat](str_repeat.html) | Repeat a string |
| [str_replace](str_replace.html) | Replace all occurrences |
| [str_split](str_split.html) | Split a string on a delimiter |
| [str_sprintf](str_sprintf.html) | Format a string |
| [str_string](str_string.html) | Convert to string |
| [str_substring](str_substring.html) | Extract substring |
| [str_trim](str_trim.html) | Trim whitespace |
| [str_trunc](str_trunc.html) | Truncate strings for display |
| [str_words](str_words.html) | Split string into words |
| [subgraph](subgraph.html) | Extract Connected Subgraph |
| [sum](sum.html) | Sum of numeric values |
| [summarize](summarize.html) | Summarize data |
| [summary](summary.html) | Model Summary |
| [swap](swap.html) | Swap a Pipeline Node Implementation |
| [t_doc](t_doc.html) | Generate Documentation |
| [t_make](t_make.html) | Build Pipeline Internally |
| [t_read_json](t_read_json.html) | Read Value from JSON |
| [t_read_onnx](t_read_onnx.html) | Read an ONNX model file |
| [t_read_pmml](t_read_pmml.html) | Read a PMML model file |
| [t_run](t_run.html) | Run a T script |
| [t_test](t_test.html) | Run tests |
| [t_write_json](t_write_json.html) | Write Value to JSON |
| [tail](tail.html) | Get the last n rows/items |
| [tan](tan.html) | Tangent |
| [tanh](tanh.html) | Hyperbolic tangent |
| [to_array](to_array.html) | Convert to NDArray |
| [to_float](to_float.html) | Convert to Float |
| [to_integer](to_integer.html) | Convert to Integer |
| [to_lower](to_lower.html) | Convert to lowercase |
| [to_numeric](to_numeric.html) | Convert to Numeric |
| [to_upper](to_upper.html) | Convert to uppercase |
| [today](today.html) | Get the current date |
| [trace_nodes](trace_nodes.html) | Trace Pipeline Nodes |
| [transpose](transpose.html) | Transpose matrix |
| [trim_end](trim_end.html) | Trim trailing whitespace |
| [trim_start](trim_start.html) | Trim leading whitespace |
| [trimmed_mean](trimmed_mean.html) | Trimmed mean |
| [trunc](trunc.html) | Truncate values |
| [type](type.html) | Get the type name of a value |
| [tz](tz.html) | Extract the timezone label |
| [uncount](uncount.html) | Expand rows by weight |
| [ungroup](ungroup.html) | Remove grouping |
| [union](union.html) | Combine two pipelines |
| [unite](unite.html) | Combine multiple columns into one character column |
| [unnest](unnest.html) | Expand nested columns |
| [update_flake_lock](update_flake_lock.html) | Update Dependencies |
| [upstream_of](upstream_of.html) | Extract Upstream Subgraph |
| [var](var.html) | Variance |
| [vcov](vcov.html) | Variance-Covariance Matrix |
| [wald_test](wald_test.html) | Joint Wald Test |
| [wday](wday.html) | Extract or label the weekday |
| [week](week.html) | Extract the week number |
| [where](where.html) | Select columns by predicate |
| [winsorize](winsorize.html) | Winsorize values |
| [with_tz](with_tz.html) | Convert a datetime to a new timezone |
| [write_arrow](write_arrow.html) | Write Arrow IPC file |
| [write_csv](write_csv.html) | Write CSV file |
| [write_text](write_text.html) | Write text to a file |
| [yday](yday.html) | Extract the day of year |
| [year](year.html) | Extract the year component |


# FILE: docs/reference/index_of.md

# index_of

Find index of substring

Returns the index of the first occurrence of `sub` in `s`, or -1 if not found.

## Parameters

- **s** (`String`): The search string.

- **sub** (`String`): The substring to find.


## Returns

The index of the first occurrence.



# FILE: docs/reference/inner_join.md

# inner_join

Join matching rows

Joins two DataFrames and keeps only rows whose keys match in both inputs.



# FILE: docs/reference/inspect_node.md

# inspect_node

Inspect Pipeline Node Metadata

Returns a dictionary with metadata about a computed node, including its name, runtime, artifact path, serializer, class, and dependencies.

## Parameters

- **node** (`ComputedNode`): A computed node value (e.g. from a built pipeline).


## Returns

A dictionary with keys = name, runtime, path, serializer, class, dependencies.

## See Also

[rebuild_node](rebuild_node.html), [read_node](read_node.html)



# FILE: docs/reference/inspect_pipeline.md

# inspect_pipeline

Inspect Pipeline Logs

Reads the latest (or specified) build log and returns a DataFrame showing the pipeline status.

## Parameters

- **which_log** (`String`): (Optional) A regex pattern to match a specific build log filename.


## Returns

A DataFrame with columns = derivation, build_success, path, output.



# FILE: docs/reference/intent_fields.md

# intent_fields

Get All Intent Fields

Returns all fields of an Intent object as a dictionary.

## Parameters

- **intent** (`Intent`): The intent object.


## Returns

The intent fields.

## See Also

[intent_get](intent_get.html)



# FILE: docs/reference/intent_get.md

# intent_get

Get Intent Field

Retrieves a field from an Intent object.

## Parameters

- **intent** (`Intent`): The intent object.

- **key** (`String`): The field name.


## Returns

The field value.

## See Also

[intent_fields](intent_fields.html)



# FILE: docs/reference/intersect.md

# intersect

Keep shared pipeline nodes

Returns the nodes from the first pipeline whose names also appear in the second.



# FILE: docs/reference/interval.md

# interval

Create an interval

Builds an interval from two Date or Datetime endpoints.



# FILE: docs/reference/inv.md

# inv

Matrix inverse

Computes the multiplicative inverse of a square matrix.

## Parameters

- **matrix** (`NDArray`): The matrix to invert.


## Returns

The inverse matrix.

## See Also

[matmul](matmul.html)



# FILE: docs/reference/iota.md

# iota

Create a vector of ones

Creates a vector of length n filled with 1.0. Use with `seq` or `ndarray` for more complex interactions.

## Parameters

- **n** (`Int`): The length of the vector.


## Returns

A vector of ones.

## Examples

```t
iota(3)
-- Returns = [1.0, 1.0, 1.0]
```

## See Also

[ndarray](ndarray.html), [seq](seq.html)



# FILE: docs/reference/iqr.md

# iqr

Interquartile range

Compute Q3 - Q1 using quantiles.

## Parameters

- **x** (`Vector`): | List Numeric input.

- **na_rm** (`Bool`): = false Remove NA values first.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/is_character.md

# is_character

Check for character columns

Predicate helper for string columns or string vectors.



# FILE: docs/reference/is_empty.md

# is_empty

Check if string is empty

Returns true if the string has length 0.

## Parameters

- **s** (`String`): The string to check.


## Returns

True if empty, false otherwise.



# FILE: docs/reference/is_error.md

# is_error

Check if a value is an Error

Returns true if the value is an Error object, false otherwise.

## Parameters

- **x** (`Any`): The value to check.


## Returns

True if x is an Error.

## Examples

```t
is_error(error("Something went wrong"))
-- Returns = true
```



# FILE: docs/reference/is_factor.md

# is_factor

Check for factor columns

Predicate helper for factor columns or factor vectors.



# FILE: docs/reference/is_leap_year.md

# is_leap_year

Check for leap years

Returns true when the supplied year or date falls in a leap year.



# FILE: docs/reference/is_logical.md

# is_logical

Check for logical columns

Predicate helper for boolean columns or boolean vectors.



# FILE: docs/reference/is_na.md

# is_na

Check for NA

Checks if a value is NA (Not Available).

## Parameters

- **x** (`Any`): The value to check.


## Returns

True if the value is NA.

## Examples

```t
is_na(na())
is_na(1)
```

## See Also

[is_error](is_error.html), [na](na.html)



# FILE: docs/reference/is_numeric.md

# is_numeric

Check for numeric columns

Predicate helper for numeric columns or numeric vectors.



# FILE: docs/reference/isoweek.md

# isoweek

Extract the ISO week number

Returns the ISO week number for Date or Datetime values.



# FILE: docs/reference/isoyear.md

# isoyear

Extract the ISO week-based year

Returns the ISO week-based year for Date or Datetime values.



# FILE: docs/reference/join.md

# str_join

Join strings with a separator

Concatenates items of a List or Vector into a single string, separated by `sep`.

## Parameters

- **items** (`List`): | Vector The items to join.
- **sep** (`String`): [Optional] The separator string. Defaults to "".

## Returns:

Returns: The joined string.

## Examples

```t
str_join(["a", "b", "c"], "-")
-- Returns = "a-b-c"
str_join(["a", "b", "c"])
-- Returns = "abc"
```

## See Also

[str_string](string.html)



# FILE: docs/reference/json_escape.md

# json_escape

JSON String Escaper

Escapes special characters for JSON compatibility.

## Parameters

- **s** (`String`): The string to escape.


## Returns

The escaped string.



# FILE: docs/reference/json_unescape.md

# json_unescape

JSON String Unescaper

Decodes escaped characters from a JSON string.

## Parameters

- **s** (`String`): The escaped string.


## Returns

The literal string.



# FILE: docs/reference/kron.md

# kron

Kronecker product

Computes the Kronecker product of two matrices.

## Parameters

- **a** (`NDArray`): First matrix.

- **b** (`NDArray`): Second matrix.


## Returns

The Kronecker product.

## See Also

[matmul](matmul.html)



# FILE: docs/reference/kurtosis.md

# kurtosis

Excess kurtosis

Compute fourth standardized moment minus 3.

## Parameters

- **x** (`Vector`): | List Numeric input.

- **na_rm** (`Bool`): = false Remove NA values first.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/lag.md

# lag

Lag values

Shifts a vector forward by n positions, filling with NA.

## Parameters

- **x** (`Vector`): The input vector.

- **n** (`Int`): (Optional) Number of positions to shift. Default is 1.


## Returns

The shifted vector.

## Examples

```t
lag([1, 2, 3])
-- Returns = [NA, 1, 2]
```

## See Also

[lead](lead.html)



# FILE: docs/reference/last_index_of.md

# last_index_of

Find last index of substring

Returns the index of the last occurrence of `sub` in `s`, or -1 if not found.

## Parameters

- **s** (`String`): The search string.

- **sub** (`String`): The substring to find.


## Returns

The index of the last occurrence.



# FILE: docs/reference/lead.md

# lead

Lead values

Shifts a vector backward by n positions, filling with NA.

## Parameters

- **x** (`Vector`): The input vector.

- **n** (`Int`): (Optional) Number of positions to shift. Default is 1.


## Returns

The shifted vector.

## Examples

```t
lead([1, 2, 3])
-- Returns = [2, 3, NA]
```

## See Also

[lag](lag.html)



# FILE: docs/reference/left_join.md

# left_join

Join rows from the left table

Joins two DataFrames and keeps every row from the left-hand side.



# FILE: docs/reference/length.md

# length

Get length

Returns the number of elements in a collection (List, Vector, Dict). This function is NOT vectorized - it always returns the count of elements. For getting the number of characters in a string, use str_nchar() instead.

## Parameters

- **x** (`List`): | Vector | Dict The collection to measure.


## Returns

The number of elements.



# FILE: docs/reference/lens.md

# lens

Lens Library

Lenses provide a way to get and set values in nested structures. Supports column-based lenses for DataFrames and Dicts.



# FILE: docs/reference/levels.md

# levels

Get factor levels

Returns the level labels stored on a factor vector.



# FILE: docs/reference/list_files.md

# list_files

List files in directory

Returns a list of files and directories in the specified path. Supports an optional regex pattern for filtering.

## Parameters

- **path** (`String`): [Optional] The directory to list. Defaults to ".".

- **pattern** (`String`): [Optional] Regex pattern to filter results.


## Returns

List of filenames.

## Examples

```t
list_files(".", pattern = "\\.t$")
```



# FILE: docs/reference/list_logs.md

# list_logs

List Pipeline Logs

Lists all available build logs in the `_pipeline/` directory.

## Returns

A DataFrame of build log files with their modification times and sizes.



# FILE: docs/reference/lm.md

# lm

Linear Model

Fits a linear regression model using Ordinary Least Squares (OLS).

## Parameters

- **data** (`DataFrame`): The data to use.

- **formula** (`Formula`): The model formula (e.g., mpg ~ wt + hp).


## Returns

A model object containing coefficients, residuals, and statistics.

## Examples

```t
model = lm(mtcars, mpg ~ wt + hp)
summary(model)
```

## See Also

[add_diagnostics](add_diagnostics.html), [fit_stats](fit_stats.html), [summary](summary.html)



# FILE: docs/reference/log.md

# log

Natural logarithm

Calculates the natural logarithm (base e) of x.

## Parameters

- **x** (`Number`): | Vector | NDArray The input value (must be positive).

- **na_ignore** (`Bool`): Whether to preserve NA values in inputs. Default is false.


## Returns

| Vector | NDArray The natural logarithm.

## Examples

```t
log(2.71828)
-- Returns = ~1.0
```

## See Also

[exp](exp.html)



# FILE: docs/reference/mad.md

# mad

Median absolute deviation

Compute scaled MAD: 1.4826 * median(|x - median(x)|).

## Parameters

- **x** (`Vector`): | List Numeric input.

- **na_rm** (`Bool`): = false Remove NA values first.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/make_date.md

# make_date

Construct a Date value

Builds a Date value from named year, month, and day components.



# FILE: docs/reference/make_datetime.md

# make_datetime

Construct a Datetime value

Builds a Datetime value from named date, time, and timezone components.



# FILE: docs/reference/make_period.md

# make_period

Create a period value

Builds a period from named year, month, day, hour, minute, and second components.



# FILE: docs/reference/map.md

# map

Map a function over a list

Applies a function to each element of a list and returns a new list of results.

## Parameters

- **list** (`List`): The input list.

- **fn** (`Function`): The function to apply to each element.


## Returns

The list of results.

## Examples

```t
map([1, 2, 3], fn(x) -> x * 2)
-- Returns = [2, 4, 6]
```



# FILE: docs/reference/matches.md

# matches

Match columns by regex

Selection helper that returns columns whose names match a regular expression.



# FILE: docs/reference/matmul.md

# matmul

Matrix multiplication

Performs matrix multiplication on two 2D NDArrays.

## Parameters

- **a** (`NDArray`): Left matrix.

- **b** (`NDArray`): Right matrix.


## Returns

The product of the two matrices.

## See Also

[diag](diag.html), [kron](kron.html), [inv](inv.html)



# FILE: docs/reference/max.md

# max

Maximum value

Returns the maximum value in a vector or list.

## Parameters

- **x** (`Vector`): | List The numeric data.

- **na_rm** (`Bool`): Whether to remove NA values. Default is false.


## Returns

The maximum value.

## Examples

```t
max([1, 2, 3])
-- Returns = 3.0
```

## See Also

[min](min.html)



# FILE: docs/reference/mday.md

# mday

Extract the day of month

Alias for day() that returns the day-of-month component from Date or Datetime values.



# FILE: docs/reference/mean.md

# mean

Compute arithmetic mean of numeric values

The mean is the sum of values divided by the count. This function handles NA values explicitly through the na_rm parameter.

## Parameters

- **x** (`Vector[Float]`): | List[Float] Input numeric data. Must contain at least one value.

- **na_rm** (`Bool`): = false Remove NA values before computation.


## Returns

| NA The arithmetic mean, or NA if input contains NA and na_rm is false

## Examples

```t
mean([1, 2, 3])
-- Returns = 2.0

mean([1, NA, 3], na_rm = true)
-- Returns = 2.0

```

## See Also

[sum](sum.html), [sd](sd.html), [median](median.html)



# FILE: docs/reference/median.md

# median

Median

Compute median of numeric values.

## Parameters

- **x** (`Vector`): | List Numeric input.

- **na_rm** (`Bool`): = false Remove NA values first.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/min.md

# min

Minimum value

Returns the minimum value in a vector or list.

## Parameters

- **x** (`Vector`): | List The numeric data.

- **na_rm** (`Bool`): Whether to remove NA values. Default is false.


## Returns

The minimum value.

## Examples

```t
min([1, 2, 3])
-- Returns = 1.0
```

## See Also

[max](max.html)



# FILE: docs/reference/min_rank.md

# min_rank

Minimum Rank

Assigns the minimum rank to ties, leaving gaps in ranks.

## Parameters

- **x** (`Vector`): The input vector.


## Returns

The ranks.

## Examples

```t
min_rank([1, 2, 2, 4])
-- Returns = [1, 2, 2, 4]
```

## See Also

[row_number](row_number.html), [dense_rank](dense_rank.html)



# FILE: docs/reference/minute.md

# minute

Extract the minute

Returns the minute component from Datetime values.



# FILE: docs/reference/mode.md

# mode

Mode

Return most frequent value.

## Parameters

- **x** (`Vector`): | List Input values.


## Returns

The most frequent value from the input (or NA if empty).



# FILE: docs/reference/modify.md

# modify

Multiple Lens Transformations

Applies a sequence of lens-based transformations to the same data structure. Takes pairs of (lens, function).

## Parameters

- **data** (`Any`): The input structure.

- **...** (`Lens,`): Function Sequence of lens and transformation function pairs.


## Returns

The final updated structure.



# FILE: docs/reference/month.md

# month

Extract or label the month

Returns the month number, or month labels when requested, from Date or Datetime values.



# FILE: docs/reference/mutate.md

# mutate

Mutate DataFrame

Adds new columns or modifies existing ones.

## Parameters

- **df** (`DataFrame`): The input DataFrame.

- **...** (`Expressions`): Key-value pairs of new columns.


## Returns

The mutated DataFrame.

## Examples

```t
mutate(mtcars, $ratio = $mpg / $hp)
```

## See Also

[select](select.html), [summarize](summarize.html)



# FILE: docs/reference/mutate_node.md

# mutate_node

Mutate Pipeline Node Metadata

Modifies metadata fields on pipeline nodes. Supports a `where` named argument to scope changes to a subset of nodes. Without `where`, all nodes are affected.  Mutable metadata fields: `noop` (Bool), `serializer` (String), `deserializer` (String), `runtime` (String).  The `where` clause uses NSE (`$field`) just like `filter_node`.

## Parameters

- **p** (`Pipeline`): The pipeline to modify.

- **...** (`KeywordArgs`): Metadata assignments as `$field = value` pairs.

- **where** (`Function`): (Optional) Predicate scoping which nodes are updated.


## Returns

A new pipeline with updated node metadata.

## Examples

```t
p |> mutate_node($noop = true)
p |> mutate_node($serializer = "pmml", where = $runtime == "R")
```

## See Also

[rename_node](rename_node.html), [filter_node](filter_node.html)



# FILE: docs/reference/na_bool.md

# na_bool

Boolean NA

Represents a missing boolean value.

## Returns



## See Also

[na](na.html)



# FILE: docs/reference/na_float.md

# na_float

Float NA

Represents a missing float value.

## Returns



## See Also

[na](na.html)



# FILE: docs/reference/na_int.md

# na_int

Integer NA

Represents a missing integer value.

## Returns



## See Also

[na](na.html)



# FILE: docs/reference/na.md

# na

Generic NA

Represents a missing value of generic type.

## Returns



## See Also

[is_na](is_na.html)



# FILE: docs/reference/na_string.md

# na_string

String NA

Represents a missing string value.

## Returns



## See Also

[na](na.html)



# FILE: docs/reference/nchar.md

# str_nchar

Get character count

Returns the number of characters in a string. Vectorized.

## Parameters

- **x** (`String`): | Vector[String] The input string(s).

## Returns:

Returns: | Vector[Int] The number of characters.



# FILE: docs/reference/ncol.md

# ncol

Number of columns

Returns the number of columns in a DataFrame.

## Parameters

- **df** (`DataFrame`): The input DataFrame.


## Returns

The number of columns.

## Examples

```t
ncol(mtcars)
```

## See Also

[colnames](colnames.html), [nrow](nrow.html)



# FILE: docs/reference/ndarray_data.md

# ndarray_data

Get NDArray data

Returns the flattened data of an NDArray as a list of floats.

## Parameters

- **array** (`NDArray`): The array to inspect.


## Returns

The flat data.



# FILE: docs/reference/ndarray.md

# ndarray

Create an N-dimensional array

Creates a new NDArray from a list or vector of data, optionally specifying the shape. If shape is not provided, it is inferred from the nested structure of the input list.

## Parameters

- **data** (`List`): | Vector The data to populate the array. Can be nested lists.

- **shape** (`List[Int]`): (Optional) The dimensions of the array.


## Returns

The created N-dimensional array.

## Examples

```t
ndarray([1, 2, 3, 4], shape = [2, 2])
ndarray([[1, 2], [3, 4]])
```

## See Also

[shape](shape.html), [reshape](reshape.html)



# FILE: docs/reference/n_distinct.md

# n_distinct

Count distinct values

Returns the number of distinct values in a vector or list. Inside `summarize()`, this acts as an aggregation expression.

## Parameters

- **x** (`Vector`): | List The input values.


## Returns

The number of distinct values.

## Examples

```t
summarize(df, $unique_species = n_distinct($species))
```

## See Also

[distinct](distinct.html), [summarize](summarize.html)



# FILE: docs/reference/nesting.md

# nesting

Helper to find combinations present in data

nesting() is used inside expand() or complete() to only use combinations that already appear in the data.

## Parameters

- **...** (`Symbol`): The columns to nest (use $col syntax).


## Returns

A special marker for expand/complete.

## Examples

```t
expand(df, nesting($year, $month))
```



# FILE: docs/reference/nest.md

# nest

Nest columns into sub-dataframes

Packs selected columns into nested DataFrame values grouped by the remaining columns. Supports flexible column selection using symbols, strings, or selection helpers (like starts_with, ends_with).  If the DataFrame is already grouped (via group_by()) and no columns are specified, nest() will automatically nest all columns except the grouping keys.

## Parameters

- **data** (`Selection`): (Optional) Columns or matchers to nest.

- **df** (`DataFrame`): The DataFrame to nest.

- **name** (`String`): (Optional) Name for the new nested column, defaults to "data".

- **...** (`Selection`): (Optional) Positional columns to nest if 'data' is not provided.


## Returns

A new DataFrame with grouped keys and a nested list-column.



# FILE: docs/reference/n.md

# n

Group size aggregation

Returns the number of rows in the current aggregation context. Use this inside `summarize()` to count rows per group.

## Returns

The row count.

## Examples

```t
df |> group_by($species) |> summarize($rows = n())
```

## See Also

[count](count.html), [summarize](summarize.html)



# FILE: docs/reference/nobs.md

# nobs

Number of Observations

Returns the number of observations used to fit a model.

## Parameters

- **model** (`Model`): The model object.


## Returns

The number of observations.

## Examples

```t
model = lm(mpg ~ wt, data = mtcars)
n = nobs(model)
```



# FILE: docs/reference/node_lens.md

# node_lens

Pipeline Node Lens

Targets the cached result value of a specific node in a Pipeline.

## Parameters

- **node_name** (`String`): The name of the node.


## Returns

A lens for the node's value.



# FILE: docs/reference/node.md

# node

Configure a Pipeline Node

Configure execution settings such as the runtime and custom serialized methods for a pipeline node. This function is typically used directly within a `pipeline { ... }` block to wrap expressions, enable cross-runtime evaluation, and optionally render a `.qmd` document via `runtime = Quarto`.

## Parameters

- **command** (`Any`): (Optional) The expression to evaluate inside the node. Mutually exclusive with `script`.

- **script** (`String`): (Optional) Path to an external `.R`, `.py`, or `.qmd` file to execute as the node body. Mutually exclusive with `command`. The runtime is auto-detected from the file extension when not explicitly provided.

- **runtime** (`Symbol`): (Optional) The runtime environment (T, R, Python, Quarto). Default = T.

- **serializer** (`String`): | Function (Optional) Custom serializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **deserializer** (`String`): | Function (Optional) Custom deserializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **args** (`Dict`): (Optional) Runtime/tool arguments. For Quarto, use this to pass CLI arguments such as `subcommand`, `path`, and additional options. `output_dir` is reserved and managed automatically so the rendered result is stored as the node artifact.

- **functions** (`String`): | List[String] (Optional) Files to source before execution.

- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.

- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.


## Returns

The evaluated return value of the command.



# FILE: docs/reference/normalize.md

# normalize

Normalize values

Min-max normalize values to [0, 1].

## Parameters

- **x** (`Vector`): | List Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/now.md

# now

Get the current datetime

Returns the current datetime and accepts an optional timezone override.



# FILE: docs/reference/nrow.md

# nrow

Number of rows

Returns the number of rows in a DataFrame or the length of a vector.

## Parameters

- **x** (`DataFrame`): | Vector The input data.


## Returns

The number of rows/elements.

## Examples

```t
nrow(mtcars)
```

## See Also

[length](length.html), [ncol](ncol.html)



# FILE: docs/reference/ntile.md

# ntile

N-tiles

Divides the vector into n buckets.

## Parameters

- **x** (`Vector`): The input vector.

- **n** (`Int`): Number of buckets.


## Returns

Bucket indices (1 to n).

## See Also

[min_rank](min_rank.html)



# FILE: docs/reference/ordered.md

# ordered

Create ordered factors

Creates factor vectors marked as ordered for ordinal comparisons.



# FILE: docs/reference/over.md

# over

Transform Focused Value

Applies a function to the value focused by a lens and returns the updated structure.

## Parameters

- **data** (`Any`): The input structure.

- **lens** (`Lens`): The lens defining the focus.

- **func** (`Function`): The transformation function.


## Returns

The updated structure.



# FILE: docs/reference/package_info.md

# package_info

Get package information

Returns metadata for a specific package, including its description and functions.

## Parameters

- **name** (`String`): The name of the package.


## Returns

Package metadata.

## Examples

```t
package_info("stats")
```

## See Also

[packages](packages.html)



# FILE: docs/reference/packages.md

# packages

List available packages

Returns a list of all standard packages available in the environment.

## Returns

List of package metadata.

## Examples

```t
packages()
```

## See Also

[package_info](package_info.html)



# FILE: docs/reference/parallel.md

# parallel

Combine Pipelines in Parallel

Combines two pipelines that are intended to run independently. Errors immediately if any node name exists in both pipelines. Outputs are not automatically wired.

## Parameters

- **p1** (`Pipeline`): The first pipeline.

- **p2** (`Pipeline`): The second pipeline.


## Returns

A merged pipeline with all nodes from both.

## Examples

```t
parallel(p_r_model, p_py_model)
```

## See Also

[union](union.html), [chain](chain.html)



# FILE: docs/reference/parse_date.md

# parse_date

Parse dates from strings

Parses strings or string vectors into Date values using an explicit format string.



# FILE: docs/reference/parse_datetime.md

# parse_datetime

Parse datetimes from strings

Parses strings or string vectors into Datetime values using an explicit format string and optional timezone.



# FILE: docs/reference/parse_file.md

# parse_file

Parse T-Doc Comments

Scans a source file and extracts all T-Doc documentation blocks (lines starting with `--#`). Parses the tags (`@name`, `@param`, `@return`, etc.) into structured documentation entries.

## Parameters

- **filename** (`String`): The path to the source file to parse.


## Returns

A list of parsed documentation entries.



# FILE: docs/reference/patch.md

# patch

Overlay one pipeline onto another

Replaces matching nodes in one pipeline with definitions from another pipeline.



# FILE: docs/reference/path_abs.md

# path_abs

Resolve relative path to absolute

## Parameters

- **path** (`String`): A relative or absolute path.


## Returns

The absolute path resolved against the current working directory.

## Examples

```t
path_abs("data.csv")          # => "/cwd/data.csv"
path_abs("/already/absolute") # => "/already/absolute"
```



# FILE: docs/reference/path_basename.md

# path_basename

Get filename component of a path

## Parameters

- **path** (`String`): A file path.


## Returns

The final component of the path.

## Examples

```t
path_basename("/home/user/data.csv")  # => "data.csv"
```



# FILE: docs/reference/path_dirname.md

# path_dirname

Get directory portion of a path

## Parameters

- **path** (`String`): A file path.


## Returns

The directory portion of the path.

## Examples

```t
path_dirname("/home/user/data.csv")  # => "/home/user"
```



# FILE: docs/reference/path_ext.md

# path_ext

Get file extension

## Parameters

- **path** (`String`): A file path.


## Returns

| NA The file extension including the leading dot, or null if none.

## Examples

```t
path_ext("data.csv")    # => ".csv"
path_ext("Makefile")    # => null
```



# FILE: docs/reference/path_join.md

# path_join

Join multiple path segments

## Parameters

- **...** (`String`): One or more path segments to join.


## Returns

The joined path.

## Examples

```t
path_join("/home/user", "project", "data.csv")  # => "/home/user/project/data.csv"
```



# FILE: docs/reference/path_stem.md

# path_stem

Get filename without extension

## Parameters

- **path** (`String`): A file path.


## Returns

The filename without its extension.

## Examples

```t
path_stem("data.csv")        # => "data"
path_stem("archive.tar.gz")  # => "archive.tar"
```



# FILE: docs/reference/pchisq.md

# pchisq

Chi-squared distribution CDF

Returns cumulative probabilities from the chi-squared distribution.



# FILE: docs/reference/percent_rank.md

# percent_rank

Percent Rank

Calculates the proportional rank (0 to 1).

## Parameters

- **x** (`Vector`): The input vector.


## Returns

The percent rank.

## See Also

[cume_dist](cume_dist.html)



# FILE: docs/reference/pf.md

# pf

F distribution CDF

Returns cumulative probabilities from the F distribution.



# FILE: docs/reference/pipeline_assert.md

# pipeline_assert

Assert Pipeline Validity

Validates the pipeline and returns it unchanged if valid. Throws the first validation error found if the pipeline is invalid.

## Parameters

- **p** (`Pipeline`): The pipeline to validate.


## Returns

The same pipeline if valid.

## Examples

```t
p |> pipeline_assert
```

## See Also

[pipeline_cycles](pipeline_cycles.html), [pipeline_validate](pipeline_validate.html)



# FILE: docs/reference/pipeline_copy.md

# pipeline_copy

Copy Pipeline Node Artifacts to Local Directory

Copies built artifacts from the Nix store to a local directory for easier inspection. By default copies all nodes from the latest build to `pipeline-output/`.

## Parameters

- **node** (`String`): (Optional) The node name to copy. If null, copies all nodes.

- **target_dir** (`String`): (Optional) The destination directory. Default is "pipeline-output".

- **dir_mode** (`String`): (Optional) POSIX mode for directories (e.g. "0755").

- **file_mode** (`String`): (Optional) POSIX mode for files (e.g. "0644").


## Returns

A success message or Error.



# FILE: docs/reference/pipeline_cycles.md

# pipeline_cycles

Detect Pipeline Cycles

Returns a list of node names involved in dependency cycles. A well-formed pipeline should always return an empty list.

## Parameters

- **p** (`Pipeline`): The pipeline.


## Returns

Names of nodes in cycles (empty if DAG is valid).

## Examples

```t
pipeline_cycles(p)
```

## See Also

[pipeline_assert](pipeline_assert.html), [pipeline_validate](pipeline_validate.html)



# FILE: docs/reference/pipeline_deps.md

# pipeline_deps

List Node Dependencies

Returns a dictionary mapping node names to their dependencies.

## Parameters

- **p** (`Pipeline`): The pipeline.


## Returns

The dependency graph.

## See Also

[pipeline_nodes](pipeline_nodes.html)



# FILE: docs/reference/pipeline_depth.md

# pipeline_depth

Maximum Topological Depth

Returns the maximum topological depth of any node in the pipeline. Root nodes have depth 0.

## Parameters

- **p** (`Pipeline`): The pipeline.


## Returns

The maximum depth.

## Examples

```t
pipeline_depth(p)
```

## See Also

[pipeline_to_frame](pipeline_to_frame.html), [pipeline_roots](pipeline_roots.html)



# FILE: docs/reference/pipeline_dot.md

# pipeline_dot

Export Pipeline as DOT Graph

Returns a string containing a Graphviz DOT representation of the pipeline's dependency graph, suitable for visualization.

## Parameters

- **p** (`Pipeline`): The pipeline.


## Returns

A DOT graph string.

## Examples

```t
pipeline_dot(p)
```

## See Also

[pipeline_edges](pipeline_edges.html), [pipeline_print](pipeline_print.html)



# FILE: docs/reference/pipeline_edges.md

# pipeline_edges

Pipeline Dependency Edges

Returns a list of dependency pairs, each as a two-element list `[from, to]` representing an edge from a dependency to a dependent node.

## Parameters

- **p** (`Pipeline`): The pipeline.


## Returns

A list of [dependency, dependent] pairs.

## Examples

```t
pipeline_edges(p)
```

## See Also

[pipeline_leaves](pipeline_leaves.html), [pipeline_roots](pipeline_roots.html), [pipeline_deps](pipeline_deps.html), [pipeline_nodes](pipeline_nodes.html)



# FILE: docs/reference/pipeline_leaves.md

# pipeline_leaves

Pipeline Leaf Nodes

Returns the names of all leaf nodes — nodes that no other node depends on.

## Parameters

- **p** (`Pipeline`): The pipeline.


## Returns

Names of leaf nodes.

## Examples

```t
pipeline_leaves(p)
```

## See Also

[pipeline_nodes](pipeline_nodes.html), [pipeline_roots](pipeline_roots.html)



# FILE: docs/reference/pipeline_node.md

# pipeline_node

Get Pipeline Node

Retrieves the value of a specific node in the pipeline.

## Parameters

- **p** (`Pipeline`): The pipeline.

- **name** (`String`): The node name.


## Returns

The value of the node.

## See Also

[pipeline_nodes](pipeline_nodes.html)



# FILE: docs/reference/pipeline_nodes.md

# pipeline_nodes

List Pipeline Nodes

Returns a list of node names in the pipeline.

## Parameters

- **p** (`Pipeline`): The pipeline.


## Returns

The node names.

## See Also

[pipeline_deps](pipeline_deps.html), [pipeline_node](pipeline_node.html)



# FILE: docs/reference/pipeline_print.md

# pipeline_print

Pretty-Print a Pipeline

Prints a human-readable summary of the pipeline nodes to stdout, showing each node's name, runtime, depth, noop status, and dependencies.

## Parameters

- **p** (`Pipeline`): The pipeline to print.


## Returns



## Examples

```t
pipeline_print(p)
```

## See Also

[pipeline_dot](pipeline_dot.html), [pipeline_summary](pipeline_summary.html)



# FILE: docs/reference/pipeline_roots.md

# pipeline_roots

Pipeline Root Nodes

Returns the names of all root nodes — nodes that have no dependencies.

## Parameters

- **p** (`Pipeline`): The pipeline.


## Returns

Names of root nodes.

## Examples

```t
pipeline_roots(p)
```

## See Also

[pipeline_nodes](pipeline_nodes.html), [pipeline_leaves](pipeline_leaves.html)



# FILE: docs/reference/pipeline_run.md

# pipeline_run

Run Pipeline

Re-executes a pipeline from start to finish.

## Parameters

- **p** (`Pipeline`): The pipeline to run.


## Returns

The executed pipeline.

## See Also

[pipeline_nodes](pipeline_nodes.html)



# FILE: docs/reference/pipeline_summary.md

# pipeline_summary

Pipeline Summary

Returns a DataFrame with full metadata for every node in the pipeline. This is a convenience wrapper around `pipeline_to_frame`.

## Parameters

- **p** (`Pipeline`): The pipeline.


## Returns

A DataFrame with one row per node and all metadata columns.

## Examples

```t
pipeline_summary(p)
```

## See Also

[select_node](select_node.html), [pipeline_to_frame](pipeline_to_frame.html)



# FILE: docs/reference/pipeline_to_frame.md

# pipeline_to_frame

Convert Pipeline to DataFrame

Converts a Pipeline to a DataFrame where each row represents a node and each column represents a metadata field. This is a key inspection utility for understanding and debugging pipeline structure.  The columns returned are: - `name` — the node name (String) - `runtime` — one of "T", "R", "Python" (String) - `serializer` — e.g. "default", "pmml" (String) - `deserializer` — e.g. "default", "pmml" (String) - `noop` — whether the node is a no-op (Bool) - `deps` — names of nodes this node depends on (String, comma-separated) - `depth` — topological depth in the DAG (Int); roots are depth 0 - `command_type` — one of "command" or "script" (String)

## Parameters

- **p** (`Pipeline`): The pipeline to convert.


## Returns

A DataFrame with one row per node.

## Examples

```t
pipeline_to_frame(p)
```

## See Also

[pipeline_nodes](pipeline_nodes.html), [select_node](select_node.html)



# FILE: docs/reference/pipeline_validate.md

# pipeline_validate

Validate a Pipeline

Checks a pipeline for structural errors without throwing. Returns a list of error messages. An empty list means the pipeline is valid.  Checks performed: - No dependency cycles - All referenced dependencies exist as nodes in the pipeline

## Parameters

- **p** (`Pipeline`): The pipeline to validate.


## Returns

A list of validation error messages (empty = valid).

## Examples

```t
pipeline_validate(p)
```

## See Also

[pipeline_cycles](pipeline_cycles.html), [pipeline_assert](pipeline_assert.html)



# FILE: docs/reference/pivot_longer.md

# pivot_longer

Pivot longer

Lengthens data, increasing the number of rows and decreasing the number of columns.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **...** (`Symbol`): The columns to pivot into longer format (use $col syntax).

- **names_to** (`String`): (Optional) The name of the new column to hold the column names. Defaults to "name".

- **values_to** (`String`): (Optional) The name of the new column to hold the values. Defaults to "value".


## Returns

The pivoted DataFrame.

## Examples

```t
pivot_longer(df, $A, $B, names_to = "name", values_to = "value")
```



# FILE: docs/reference/pivot_wider.md

# pivot_wider

Pivot wider

Widens data, increasing the number of columns and decreasing the number of rows.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **names_from** (`Symbol`): The column whose values become output column names (use $col syntax).

- **values_from** (`Symbol`): The column whose values fill the new columns (use $col syntax).


## Returns

The pivoted DataFrame.

## Examples

```t
pivot_wider(df, names_from = $name, values_from = $value)
```



# FILE: docs/reference/pm.md

# pm

Check whether a time is after noon

Returns true for Datetime values whose hour is 12 or later.



# FILE: docs/reference/pnorm.md

# pnorm

Normal distribution CDF

Returns cumulative probabilities from the standard normal distribution.



# FILE: docs/reference/poly.md

# poly

Polynomial basis expansion

Generates a basis of polynomial terms for a numeric vector.

## Parameters

- **x** (`Vector[Number]`): | List[Number] The vector to expand.

- **degree** (`Int`): The degree of the polynomial.

- **raw** (`Bool`): = false If true, return raw powers instead of orthogonal polynomials.


## Returns

A named list of polynomial terms.

## Examples

```t
mutate(df, !!!poly($age, 3, raw = true))
```



# FILE: docs/reference/populate_pipeline.md

# populate_pipeline

Populate Pipeline

Generates the `_pipeline/` directory with `pipeline.nix` and `dag.json`. Optionally builds the pipeline.

## Parameters

- **p** (`Pipeline`): The pipeline to populate.

- **build** (`Bool`): (Optional) Whether to trigger the Nix build immediately. Defaults to false.

- **verbose** (`Int`): (Optional) Nix build verbosity level. `0` keeps build failures quiet; values above `0` print failed node logs.


## Returns

A status message or the output path if build=true.



# FILE: docs/reference/pow.md

# pow

Power function

Calculates base raised to the power of exponent.

## Parameters

- **base** (`Number`): | Vector | NDArray The base.

- **exponent** (`Number`): The exponent.

- **na_ignore** (`Bool`): Whether to preserve NA values in inputs. Default is false.


## Returns

| Vector | NDArray The result of base ^ exponent.

## Examples

```t
pow(2, 3)
-- Returns = 8.0
```

## See Also

[exp](exp.html), [sqrt](sqrt.html)



# FILE: docs/reference/predict.md

# predict

Model Prediction

Calculates predicted values for a model object. Standardized on JPMML as the sole scoring authority for PMML models. Native OCaml implementation is maintained for linear models and as a validation fallback for trees.

## Parameters

- **data** (`DataFrame`): The new data used for prediction.

- **model** (`Model`): The model object (PMML, ONNX, or T-native).


## Returns

| DataFrame The predicted values. For JPMML-backed PMML models (e.g. classification),

## See Also

[t_read_onnx](t_read_onnx.html), [t_read_pmml](t_read_pmml.html), [lm](lm.html)



# FILE: docs/reference/pretty_print.md

# pretty_print

Pretty-print a value

Prints a formatted representation of a value. DataFrames are printed as tables.

## Parameters

- **x** (`Any`): The value to print.


## Returns



## Examples

```t
pretty_print(df)
```

## See Also

[print](print.html)



# FILE: docs/reference/print.md

# print

Print values to standard output

Prints one or more values to stdout, separated by spaces, followed by a newline. Strings are printed without quotes.

## Parameters

- **...** (`Any`): Values to print.


## Returns



## Examples

```t
print("Hello", "World")
-- Output = Hello World
```



# FILE: docs/reference/prune.md

# prune

Prune Pipeline Leaf Nodes

Removes all leaf nodes — nodes that have no downstream dependents (nothing depends on them). This is useful for cleaning up intermediate pipelines after `filter_node` or `difference` operations.

## Parameters

- **p** (`Pipeline`): The pipeline to prune.


## Returns

A new pipeline with leaf nodes removed.

## Examples

```t
p |> difference(p_remove) |> prune
```

## See Also

[difference](difference.html), [filter_node](filter_node.html)



# FILE: docs/reference/pt.md

# pt

Student t distribution CDF

Returns cumulative probabilities from the Student t distribution.



# FILE: docs/reference/pull.md

# pull

Extract column as vector

Extracts a single column from a DataFrame as a Vector.

## Parameters

- **df** (`DataFrame`): The input DataFrame.

- **col** (`String`): The column name.


## Returns

The column data.

## Examples

```t
pull(mtcars, "mpg")
```

## See Also

[select](select.html)



# FILE: docs/reference/pyn.md

# pyn

Configure a Python Pipeline Node

A convenience wrapper around `node()` with `runtime = "Python"`. Used directly within a `pipeline { ... }` block to execute Python code.

## Parameters

- **command** (`Any`): (Optional) The expression to evaluate inside the Python node (must be enclosed in `<{ ... }>` blocks). Mutually exclusive with `script`.

- **script** (`String`): (Optional) Path to an external `.py` file to execute as the node body. Mutually exclusive with `command`. Sets the runtime to `Python` automatically.

- **serializer** (`String`): | Function (Optional) Custom serializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **deserializer** (`String`): | Function (Optional) Custom deserializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **functions** (`String`): | List[String] (Optional) Python files to source before execution.

- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.

- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.


## Returns

The evaluated return value of the command.

## See Also

[rn](rn.html), [node](node.html)



# FILE: docs/reference/qn.md

# qn

Configure a Quarto Pipeline Node

A convenience wrapper around `node()` with `runtime = "Quarto"`. Used directly within a `pipeline { ... }` block to render Quarto documents.

## Parameters

- **script** (`String`): (Optional) Path to an external `.qmd` file to render. Mutually exclusive with `command`.

- **serializer** (`String | Function`): (Optional) Custom serializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **deserializer** (`String | Function`): (Optional) Custom deserializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **env_vars** (`Dict`): (Optional) Environment variables to pass into the sandbox.

- **args** (`Dict`): (Optional) Runtime/tool arguments. Use this to pass Quarto CLI arguments such as `subcommand`, `path`, `to`, and additional options. `output_dir` is reserved and managed automatically so the rendered result is stored as the node artifact.

- **functions** (`String | List[String]`): (Optional) Files to source before execution.

- **include** (`String | List[String]`): (Optional) Additional files for the sandbox.

- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.


## Returns

The evaluated return value of the command.

## See Also

[node](node.html), [rn](rn.html), [pyn](pyn.html), [shn](shn.html)


# FILE: docs/reference/quantile.md

# quantile

Quantiles

Computes the quantile of a distribution at a specified probability.

## Parameters

- **x** (`Vector`): | List The numeric data.

- **probs** (`Float`): The probability (0 to 1).

- **na_rm** (`Bool`): (Optional) Should missing values be removed? Default is false.


## Returns

The quantile value.

## Examples

```t
quantile(x, 0.5)
-- Returns median
```

## See Also

[mean](mean.html), [median](median.html)



# FILE: docs/reference/quarter.md

# quarter

Extract the quarter

Returns the quarter number for Date or Datetime values.



# FILE: docs/reference/quo.md

# quo

Capture an expression with its lexical environment (quosure)

Captures the provided expression as a **Quosure**: a pair of the expression AST and the current lexical environment. When later evaluated with `eval()`, the expression is evaluated in the captured environment, not the caller's. This matches the semantics of `rlang::quo()` in R.

## Parameters

- **x** (`Any`): The expression to capture as a quosure.


## Returns

The captured expression with its environment.

## Examples

```t
x = 10
q = quo(1 + x)   -- captures x = 10
x = 99
eval(q)           -- returns 11, not 100
```



# FILE: docs/reference/quos.md

# quos

Capture multiple expressions with their lexical environment (quosures)

Captures one or more expressions as a List of Quosure values, each paired with the current lexical environment. Supports named arguments. Matches the semantics of `rlang::quos()` in R.

## Parameters

- **...** (`Any`): One or more expressions to capture as quosures.


## Returns

A list of captured quosures.

## Examples

```t
x = 10
qs = quos(a = 1 + x, b = 2 * x)
eval(qs$a)   -- returns 11
```



# FILE: docs/reference/range.md

# range

Range

Return min and max as a length-2 vector.

## Parameters

- **x** (`Vector`): | List Numeric input.

- **na_rm** (`Bool`): = false Remove NA values first.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/read_arrow.md

# read_arrow

Read Arrow IPC file

Reads a DataFrame from an Apache Arrow IPC (Feather v2) file.

## Parameters

- **path** (`String`): The path to the Arrow file.


## Returns

The loaded DataFrame.

## Examples

```t
df = read_arrow("data.arrow")
```

## See Also

[write_arrow](write_arrow.html)



# FILE: docs/reference/read_csv.md

# read_csv

Read CSV file

Reads a CSV file into a DataFrame.

## Parameters

- **path** (`String`): Path or URL to the CSV file.

- **separator** (`String`): (Optional) Field separator (default ",").

- **skip_header** (`Bool`): (Optional) Skip proper header parsing? (default false).

- **skip_lines** (`Int`): (Optional) Number of lines to skip at start.

- **clean_colnames** (`Bool`): (Optional) Clean column names? (default false).


## Returns

The loaded data.

## Examples

```t
df = read_csv("data.csv")
df = read_csv("data.csv", separator = ";")
```

## See Also

[write_csv](write_csv.html)



# FILE: docs/reference/read_file.md

# read_file

Read file contents

Reads the entire content of a file into a string.

## Parameters

- **path** (`String`): The path to the file.


## Returns

The file content.

## Examples

```t
read_file("config.json")
```



# FILE: docs/reference/read_log.md

# read_log

Read Node Build Log

Fetches the Nix build log for a specific node from the last build attempt.

## Parameters

- **node_name** (`String`): The name of the node to inspect.


## Returns

The build log content.



# FILE: docs/reference/read_node.md

# read_node

Read Pipeline Node Artifact

For in-memory Pipelines, returns a node record with the node value and structured diagnostics. For built pipelines, reads the artifact from the latest (or specified) build log in `_pipeline/`. Use `which_log` to read from a specific historical build ("time travel").

## Parameters

- **node** (`Pipeline`): | String | ComputedNode Pass a Pipeline for in-memory node diagnostics, or a String/ComputedNode to load a built artifact.

- **name** (`String`): (Optional) The node name to read when `node` is a Pipeline.

- **which_log** (`String`): (Optional) A regex pattern to match a specific build log filename.


## Returns

A Dict with value+diagnostics for in-memory pipelines, or the deserialized artifact for built nodes.

## See Also

[inspect_pipeline](inspect_pipeline.html), [build_pipeline](build_pipeline.html), [read_pipeline](read_pipeline.html)



# FILE: docs/reference/read_parquet.md

# read_parquet

Read Parquet file

Reads a DataFrame from a Parquet file using the native parquet-glib reader.

## Parameters

- **path** (`String`): Path or URL to the Parquet file.


## Returns

The loaded data.

## Examples

```t
df = read_parquet("data.parquet")
```

## See Also

[read_arrow](read_arrow.html), [read_csv](read_csv.html)



# FILE: docs/reference/read_pipeline.md

# read_pipeline

Read Pipeline Metadata

Returns a dictionary describing a materialized in-memory pipeline, including per-node diagnostics and the aggregated diagnostics summary.

## Parameters

- **p** (`Pipeline`): The pipeline to inspect.


## Returns

A dictionary with node metadata and diagnostics.

## See Also

[explain](explain.html), [read_node](read_node.html)



# FILE: docs/reference/read_registry.md

# read_registry

Registry Maintenance (Reader)

Parses a registry JSON file back into a list of name-path pairs.

## Parameters

- **path** (`String`): Source file.


## Returns

String)], String] Entries or error.



# FILE: docs/reference/rebuild_node.md

# rebuild_node

Rebuild a Pipeline Node

Rebuilds a single node from the pipeline Nix expression and returns an updated ComputedNode with the new artifact path.

## Parameters

- **node** (`ComputedNode`): A computed node value to rebuild.


## Returns

An updated ComputedNode pointing to the rebuilt artifact.

## See Also

[inspect_node](inspect_node.html), [read_node](read_node.html)



# FILE: docs/reference/relocate.md

# relocate

Move columns to a new position

Reorders DataFrame columns by moving selected columns before or after another column.



# FILE: docs/reference/rename.md

# rename

Rename DataFrame columns

Renames selected DataFrame columns using named arguments.



# FILE: docs/reference/rename_node.md

# rename_node

Rename a Pipeline Node

Renames a single node and rewires all dependency edges that referenced the old name to the new name. This is the canonical way to resolve name collisions before set operations.

## Parameters

- **p** (`Pipeline`): The pipeline.

- **old_name** (`String`): The current name of the node.

- **new_name** (`String`): The desired new name.


## Returns

A new pipeline with the node renamed.

## Examples

```t
p |> rename_node("model_r", "model_r_v2")
```

## See Also

[filter_node](filter_node.html), [mutate_node](mutate_node.html)



# FILE: docs/reference/replace_first.md

# replace_first

Replace first occurrence

Replaces only the first occurrence of `old` with `new_` in `s`.

## Parameters

- **s** (`String`): The input string.

- **old** (`String`): The substring to replace.

- **new_** (`String`): The replacement string.


## Returns

The modified string.



# FILE: docs/reference/replace.md

# str_replace

Replace all occurrences

Replaces all occurrences of `old` with `new_` in `s`.

## Parameters

- **s** (`String`): The input string.
- **old** (`String`): The substring to replace.
- **new_** (`String`): The replacement string.

## Returns:

Returns: The modified string.



# FILE: docs/reference/replace_na.md

# replace_na

Replace missing values

replace_na() replaces missing values with specified values.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **replace** (`Dict`): A list of named values to use for replacing NA.


## Returns

The DataFrame with NA replaced.

## Examples

```t
replace_na(df, [age: 0, score = 0])
```



# FILE: docs/reference/reshape.md

# reshape

Reshape an NDArray

Returns a new NDArray with the same data but different dimensions. The total number of elements must remain the same.

## Parameters

- **array** (`NDArray`): The array to reshape.

- **shape** (`List[Int]`): The new dimensions.


## Returns

A new array with the specified shape.

## Examples

```t
reshape(arr, [4, 1])
```

## See Also

[shape](shape.html), [ndarray](ndarray.html)



# FILE: docs/reference/residuals.md

# residuals

Model Residuals

Computes residuals for a model given a dataset.

## Parameters

- **data** (`DataFrame`): Input data.

- **model** (`Model`): The model object.

- **type** (`String`): (Optional) Type of residuals = "response" (default) or "pearson".


## Returns

Columns = `actual`, `fitted`, `resid`.

## Examples

```t
res = residuals(mtcars, model)
res_p = residuals(mtcars, model, type = "pearson")
```



# FILE: docs/reference/rewire.md

# rewire

Rewire a Node's Dependencies

Reroutes a node's declared dependencies. The `replace` argument is a named list (or Dict) mapping old dependency names to new ones. Only the named node's dependency list is updated.

## Parameters

- **p** (`Pipeline`): The pipeline.

- **name** (`String`): The name of the node whose deps should change.

- **replace** (`List[String]`): A named list mapping old dep names to new ones.


## Returns

A new pipeline with updated dependency edges.

## Examples

```t
p |> rewire("model_py", replace = list(data = "data_v2"))
```

## See Also

[rename_node](rename_node.html), [swap](swap.html)



# FILE: docs/reference/rm.md

# rm

Remove objects from the environment

Removes one or more variables from the current environment by name. Supports bare symbols (R-style selective removal), strings, and lists of names via the `list` parameter.

## Parameters

- **...** (`Symbol`): | String One or more variables to remove.

- **list** (`List[String]`): (Optional) A list of variable names to remove.


## Returns



## Examples

```t
x = 10; y = 20
rm(x, y)          -- Removes x and y

z = 30
rm("z")           -- Removes z

vars = ["a", "b"]
rm(list = vars)   -- Removes variables 'a' and 'b'

```



# FILE: docs/reference/rn.md

# rn

Configure an R Pipeline Node

A convenience wrapper around `node()` with `runtime = "R"`. Used directly within a `pipeline { ... }` block to execute R code.

## Parameters

- **command** (`Any`): (Optional) The expression to evaluate inside the R node (must be enclosed in `<{ ... }>` blocks). Mutually exclusive with `script`.

- **script** (`String`): (Optional) Path to an external `.R` file to execute as the node body. Mutually exclusive with `command`. Sets the runtime to `R` automatically.

- **serializer** (`String`): | Function (Optional) Custom serializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **deserializer** (`String`): | Function (Optional) Custom deserializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **functions** (`String`): | List[String] (Optional) R scripts to source before execution.

- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.

- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.


## Returns

The evaluated return value of the command.

## See Also

[pyn](pyn.html), [node](node.html)



# FILE: docs/reference/round_date.md

# round_date

Round dates to the nearest unit

Rounds Date or Datetime values to the nearest requested unit boundary.



# FILE: docs/reference/round.md

# round

Round values

Round numbers to a specified number of decimal digits.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.

- **digits** (`Int`): = 0 Decimal digits.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/row_lens.md

# row_lens

Row Lens

Targets a specific row in a DataFrame by its 0-based index.

## Parameters

- **i** (`Int`): The row index.


## Returns

A lens for the specified row.



# FILE: docs/reference/row_number.md

# row_number

Row Number

Returns the rank of the current row, breaking ties by index.

## Parameters

- **x** (`Vector`): The input vector.


## Returns

The ranks (1 to n).

## See Also

[dense_rank](dense_rank.html), [min_rank](min_rank.html)



# FILE: docs/reference/run_doctor.md

# run_doctor

Run Package/Project Doctor

Validates the structure of a T package or project, checking for required files, directories, valid Nix configuration, and ensuring proper documentation setup.

## Returns

Prints the validation results to the console.



# FILE: docs/reference/run.md

# run

Run a shell command

Executes a shell command and returns its stdout as a string. Raises a ShellError if the command fails (non-zero exit code).

## Parameters

- **cmd** (`String`): The shell command to execute.


## Returns

The stdout of the command.

## Examples

```t
branch = run("git rev-parse --abbrev-ref HEAD")
print(branch)
```



# FILE: docs/reference/scaffold_package.md

# scaffold_package

Scaffold a new T package

Generates the directory structure and boilerplate files for a new T language package. Creates a `DESCRIPTION.toml`, `flake.nix`, `README.md`, and an initial test setup.

## Parameters

- **opts** (`ScaffoldOptions`): The options provided via CLI (name, author, license, etc.).


## Returns

Ok(()) or an error message.



# FILE: docs/reference/scaffold_project.md

# scaffold_project

Scaffold a new T project

Generates the directory structure and boilerplate files for a new T data analysis project. Creates a `tproject.toml`, `flake.nix`, and sets up `data/`, `outputs/`, and `src/` directories.

## Parameters

- **opts** (`ScaffoldOptions`): The options provided via CLI.


## Returns

Ok(()) or an error message.



# FILE: docs/reference/scale.md

# scale

Scale values

Standardize to z-scores using sample standard deviation.

## Parameters

- **x** (`Vector`): | List Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/score.md

# score

Model Scoring

Calculates various performance metrics (RMSE, MAE, R-squared, etc.) for a model on a dataset.

## Parameters

- **data** (`DataFrame`): The dataset to score.

- **model** (`Model`): The model object.


## Returns

A one-row DataFrame with metrics.

## Examples

```t
metrics = score(test_data, model)
```



# FILE: docs/reference/sd.md

# sd

Standard Deviation

Calculates the sample standard deviation of a numeric vector.

## Parameters

- **x** (`Vector`): | List The numeric data.

- **na_rm** (`Bool`): (Optional) logical. Should missing values be removed? Default is false.


## Returns

The standard deviation.

## Examples

```t
sd([1, 2, 3, 4, 5])
-- Returns = 1.5811...
```

## See Also

[var](var.html), [mean](mean.html)



# FILE: docs/reference/second.md

# second

Extract the second

Returns the second component from Datetime values.



# FILE: docs/reference/select.md

# select

Select columns

Selects specific columns from a DataFrame.

## Parameters

- **df** (`DataFrame`): The input DataFrame.

- **...** (`Symbol`): Variable number of column names (e.g., $col1, $col2).


## Returns

The DataFrame with selected columns.

## Examples

```t
select(mtcars, $mpg, $wt)
```

## See Also

[mutate](mutate.html), [filter](filter.html)



# FILE: docs/reference/select_node.md

# select_node

Select Node Metadata Fields

Returns a DataFrame summarising the requested metadata fields for all nodes in the pipeline. This is a read-only inspection operation — it does not return a Pipeline.  Available fields: `$name`, `$runtime`, `$serializer`, `$deserializer`, `$noop`, `$deps`, `$depth`, `$command_type`.

## Parameters

- **p** (`Pipeline`): The pipeline to inspect.

- **...** (`Symbol`): One or more metadata field references (e.g. `$name`, `$runtime`).


## Returns

A DataFrame with the requested metadata columns.

## Examples

```t
p |> select_node($name, $runtime, $deps)
p |> select_node($name, $depth, $noop)
```

## See Also

[arrange_node](arrange_node.html), [filter_node](filter_node.html), [pipeline_to_frame](pipeline_to_frame.html)



# FILE: docs/reference/semester.md

# semester

Extract the semester

Returns 1 for the first half of the year and 2 for the second half.



# FILE: docs/reference/semi_join.md

# semi_join

Filter rows using matches in another table

Keeps rows from the left DataFrame that have a matching key in the right DataFrame.



# FILE: docs/reference/separate.md

# separate

Separate a character column into multiple columns

Given either a regular expression or a fixed position, separate() splits a single character column into multiple new columns.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **col** (`Symbol`): The column to separate (use $col syntax).

- **into** (`List[String]`): Names of the new columns to create.

- **sep** (`String`): (Optional) Regular expression or position to separate at.

- **remove** (`Bool`): (Optional) If true, remove the input column from the result.


## Returns

The separated DataFrame.

## Examples

```t
separate(df, $date, into = ["year", "month", "day"], sep = "-")
```



# FILE: docs/reference/separate_rows.md

# separate_rows

Split delimited values into rows

Expands delimited string values into multiple rows while repeating the remaining columns.



# FILE: docs/reference/seq.md

# seq

Generate a sequence of integers

Creates a list of integers from start to end, optionally with a step size.

## Parameters

- **start** (`Int`): (Optional) Starting value. Defaults to 1.

- **end** (`Int`): (Optional) Ending value. Defaults to start if by is provided.

- **by** (`Int`): (Optional) Step size. Defaults to 1 or -1.


## Returns

List of integers.

## Examples

```t
seq(5)
seq(1, 5)
seq(start = 1, end = 10, by = 2)
-- Returns = [1, 3, 5, 7, 9]
```



# FILE: docs/reference/serialize.md

# serialize

Serialize Value

Serializes a value to a `.tobj` file.

## Parameters

- **value** (`Any`): Value to serialize.

- **path** (`String`): Output file path.


## Returns



## See Also

[deserialize](deserialize.html)



# FILE: docs/reference/serialize_to_file.md

# serialize_to_file

Binary Serialization

Serializes any T value to a file using OCaml's Marshal module. Includes a content digest for integrity verification on deserialization.

## Parameters

- **path** (`String`): Destination file path.

- **value** (`Any`): The T value to serialize.


## Returns

String] Ok or error.



# FILE: docs/reference/set.md

# set

Set Focused Value

Replaces the value focused by a lens with a new value.

## Parameters

- **data** (`Any`): The input structure.

- **lens** (`Lens`): The lens defining the focus.

- **value** (`Any`): The new value to set.


## Returns

The updated structure.



# FILE: docs/reference/shape.md

# shape

Get NDArray dimensions

Returns the shape of an NDArray as a list of integers.

## Parameters

- **array** (`NDArray`): The array to inspect.


## Returns

The dimensions of the array.

## See Also

[reshape](reshape.html), [ndarray](ndarray.html)



# FILE: docs/reference/shn.md

# shn

Configure a Shell Pipeline Node

A convenience wrapper around `node()` with `runtime = "sh"`. Use `shn()` inside a `pipeline { ... }` block to run POSIX shell commands or `.sh` scripts, and optionally set `shell = "bash"` when Bash parsing is required.

## Parameters

- **command** (`Any`): (Optional) The shell command or raw shell script body to execute. Mutually exclusive with `script`.

- **script** (`String`): (Optional) Path to an external `.sh` file to execute as the node body. Mutually exclusive with `command`.

- **serializer** (`String`): | Function (Optional) Custom serializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **deserializer** (`String`): | Function (Optional) Custom deserializer strategy. Built-in values include "default", "arrow", and "pmml". Can be a string (e.g., "arrow") or an unquoted function name. Custom functions can also be used. Default = "default".

- **args** (`Dict`): | List (Optional) Runtime arguments. Lists become positional CLI arguments for exec-style nodes.

- **shell** (`String`): (Optional) Shell interpreter to invoke for shell-string mode or script-backed nodes. Default = "sh".

- **shell_args** (`List[String]`): (Optional) Additional arguments passed to the shell interpreter.

- **functions** (`String`): | List[String] (Optional) Additional files to include in the sandbox before execution.

- **include** (`String`): | List[String] (Optional) Additional files for the sandbox.

- **noop** (`Bool`): (Optional) Whether to skip execution and generate a stub. Default = false.


## Returns

The evaluated return value of the command.

## See Also

[pyn](pyn.html), [rn](rn.html), [node](node.html)



# FILE: docs/reference/show_plot.md

# show_plot

Render a plot node and open it locally

Builds or reuses an R/Python plot artifact, renders it into `_pipeline/`, and opens the rendered image with the command configured in `tproject.toml` under `[visualization-tool]`.

## Parameters

- **plot** (`Any`): A pipeline node, built node, or `read_node()` result for a plot-producing node.


## Returns

The local rendered image path.

## See Also

[build_pipeline](build_pipeline.html), [read_node](read_node.html)



# FILE: docs/reference/sigma.md

# sigma

Residual Standard Deviation

Returns the residual standard deviation (sigma) of a linear model. For GLMs, use `dispersion()` instead.

## Parameters

- **model** (`Model`): The model object.


## Returns

The Residual Standard Error.

## Examples

```t
model = lm(mpg ~ wt, data = mtcars)
s = sigma(model)
```

## See Also

[dispersion](dispersion.html)



# FILE: docs/reference/signif.md

# signif

Significant-digit rounding

Round to a fixed number of significant digits.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.

- **digits** (`Int`): Number of significant digits (> 0).


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/sign.md

# sign

Sign of number

Return -1, 0, or 1 depending on sign.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/sinh.md

# sinh

Hyperbolic sine

Compute hyperbolic sine.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/sin.md

# sin

Sine

Compute sine (radians).

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/skewness.md

# skewness

Skewness

Compute third standardized moment.

## Parameters

- **x** (`Vector`): | List Numeric input.

- **na_rm** (`Bool`): = false Remove NA values first.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/slice_max.md

# slice_max

Keep rows with the largest values

Returns the rows with the highest values in an ordering column.



# FILE: docs/reference/slice.md

# slice

Extract slice

Alias for `str_substring`. Returns the part of the string between `start` and `end` indices.

## Parameters

- **s** (`String`): The input string.

- **start** (`Int`): The starting index (inclusive).

- **end** (`Int`): The ending index (exclusive).


## Returns

The extracted substring.



# FILE: docs/reference/slice_min.md

# slice_min

Keep rows with the smallest values

Returns the rows with the lowest values in an ordering column.



# FILE: docs/reference/source.md

# source

Get function source code

Returns the source code of a function as a string. For built-in functions, it attempts to read the underlying OCaml source file.

## Parameters

- **fn** (`Function`): The function to inspect.


## Returns

The source code of the function.

## Examples

```t
source(print)
```



# FILE: docs/reference/sprintf.md

# str_sprintf

Format a string

Formats a string using C-style format specifiers. Supports %s (string), %d (integer), %f (float), and %% (literal %).

## Parameters

- **fmt** (`String`): The format string.
- **...** (`Any`): Values to substitute in the format string.

## Returns:

Returns: The formatted string.

## Examples

```t
str_sprintf("Hello, %s!", "world")
-- Returns = "Hello, world!"
str_sprintf("Value = %d", 42)
-- Returns: "Value = 42"
```



# FILE: docs/reference/sqrt.md

# sqrt

Square root

Calculates the square root of x.

## Parameters

- **x** (`Number`): | Vector | NDArray The input value (must be non-negative).

- **na_ignore** (`Bool`): Whether to preserve NA values in inputs. Default is false.


## Returns

| Vector | NDArray The square root.

## Examples

```t
sqrt(16)
-- Returns = 4.0
```

## See Also

[pow](pow.html)



# FILE: docs/reference/standardize.md

# standardize

Standardize values

Alias behavior for z-score standardization.

## Parameters

- **x** (`Vector`): | List Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/starts_with.md

# starts_with

Check if string starts with prefix

Returns true if `s` starts with the specified `prefix`.

## Parameters

- **s** (`String`): The string to check.

- **prefix** (`String`): The prefix to look for.


## Returns

True if s starts with prefix.



# FILE: docs/reference/str_count.md

# str_count

Count regex matches

Counts how many times a regular expression matches within each string.



# FILE: docs/reference/str_detect.md

# str_detect

Test whether a regex matches

Returns true when a regular expression matches a string.



# FILE: docs/reference/str_extract_all.md

# str_extract_all

Extract all regex matches

Returns every regular-expression match found in each string.



# FILE: docs/reference/str_extract.md

# str_extract

Extract the first regex match

Returns the first regular-expression match found in each string.



# FILE: docs/reference/str_flatten.md

# str_flatten

Flatten a collection of strings

Concatenates string collections into a single string with an optional separator.



# FILE: docs/reference/str_format.md

# str_format

Named string interpolation

Substitutes {name} placeholders using values from a Dict or named List. Use {{ and }} to produce literal braces in the output.

## Parameters

- **fmt** (`String`): The format string with {name} placeholders.

- **values** (`Dict`): | List The named values to substitute.


## Returns

The formatted string.

## See Also

[str_sprintf](str_sprintf.html)



# FILE: docs/reference/string.md

# str_string

Convert to string

Converts any value to its string representation.

## Parameters

- **x** (`Any`): The value to convert.

## Returns:

Returns: The string representation.

## Examples

```t
str_string(123)
-- Returns = "123"
```

## See Also

[str_join](join.html)



# FILE: docs/reference/str_join.md

# str_join

Join strings with a separator

Concatenates items of a List or Vector into a single string, separated by `sep`.

## Parameters

- **items** (`List`): | Vector The items to join.

- **sep** (`String`): [Optional] The separator string. Defaults to "".


## Returns

The joined string.

## Examples

```t
str_join(["a", "b", "c"], "-")
-- Returns = "a-b-c"
str_join(["a", "b", "c"])
-- Returns = "abc"
```

## See Also

[str_string](str_string.html)



# FILE: docs/reference/str_lines.md

# str_lines

Split string into lines

Splits on \n or \r\n. Strips trailing newline. Accepts ShellResult.

## Parameters

- **s** (`String`): | ShellResult


## Returns



## See Also

[str_split](str_split.html), [str_words](str_words.html)



# FILE: docs/reference/str_nchar.md

# str_nchar

Get character count

Returns the number of characters in a string. Vectorized.

## Parameters

- **x** (`String`): | Vector[String] The input string(s).


## Returns

| Vector[Int] The number of characters.



# FILE: docs/reference/str_pad.md

# str_pad

Pad strings to a target width

Pads strings on the left, right, or both sides until they reach a requested width.



# FILE: docs/reference/str_repeat.md

# str_repeat

Repeat a string

## Parameters

- **s** (`String`): The string to repeat.

- **n** (`Int`): Number of repetitions.


## Returns





# FILE: docs/reference/str_replace.md

# str_replace

Replace all occurrences

Replaces all occurrences of `old` with `new_` in `s`.

## Parameters

- **s** (`String`): The input string.

- **old** (`String`): The substring to replace.

- **new_** (`String`): The replacement string.


## Returns

The modified string.



# FILE: docs/reference/str_split.md

# str_split

Split a string on a delimiter

Splits a string into a list of substrings on each occurrence of `sep`. If `sep` is empty, splits into individual characters. Works transparently on ShellResult values (splits stdout).

## Parameters

- **x** (`String`): | ShellResult The string to split.

- **sep** (`String`): The delimiter to split on.


## Returns

A list of substrings.

## Examples

```t
str_split("a,b,c", ",")
-- Returns = ["a", "b", "c"]
files = ?<{ls}>; str_split(files, "\n")
```

## See Also

[str_join](str_join.html)



# FILE: docs/reference/strsplit.md

# str_split

Split a string on a delimiter

Splits a string into a list of substrings on each occurrence of `sep`. If `sep` is empty, splits into individual characters. Works transparently on ShellResult values (splits stdout).

## Parameters

- **x** (`String`): | ShellResult The string to split.
- **sep** (`String`): The delimiter to split on.

## Returns:

Returns: A list of substrings.

## Examples

```t
str_split("a,b,c", ",")
-- Returns = ["a", "b", "c"]
files = ?<{ls}>; str_split(files, "\n")
```

## See Also

[str_join](join.html)



# FILE: docs/reference/str_sprintf.md

# str_sprintf

Format a string

Formats a string using C-style format specifiers. Supports %s (string), %d (integer), %f (float), and %% (literal %).

## Parameters

- **fmt** (`String`): The format string.

- **...** (`Any`): Values to substitute in the format string.


## Returns

The formatted string.

## Examples

```t
str_sprintf("Hello, %s!", "world")
-- Returns = "Hello, world!"
str_sprintf("Value = %d", 42)
-- Returns: "Value = 42"
```



# FILE: docs/reference/str_string.md

# str_string

Convert to string

Converts any value to its string representation.

## Parameters

- **x** (`Any`): The value to convert.


## Returns

The string representation.

## Examples

```t
str_string(123)
-- Returns = "123"
```

## See Also

[str_join](str_join.html)



# FILE: docs/reference/str_substring.md

# str_substring

Extract substring

Returns the part of the string between `start` and `end` indices.

## Parameters

- **s** (`String`): The input string.

- **start** (`Int`): The starting index (inclusive).

- **end** (`Int`): The ending index (exclusive).


## Returns

The extracted substring.



# FILE: docs/reference/str_trim.md

# str_trim

Trim whitespace

Removes leading and trailing whitespace from a string. Vectorized.

## Parameters

- **s** (`String`): The string to trim.


## Returns

The trimmed string.



# FILE: docs/reference/str_trunc.md

# str_trunc

Truncate strings for display

Shortens strings to a maximum width and appends an ellipsis when needed.



# FILE: docs/reference/str_words.md

# str_words

Split string into words

Splits on whitespace, collapsing consecutive spaces. Accepts ShellResult. Note: words splits on spaces and tabs only, not newlines. For line-by-line processing use str_lines() first, then str_words() on each line.

## Parameters

- **s** (`String`): | ShellResult


## Returns



## See Also

[str_split](str_split.html), [str_lines](str_lines.html)



# FILE: docs/reference/subgraph.md

# subgraph

Extract Connected Subgraph

Returns a new pipeline containing the named node, all of its ancestors, and all of its descendants — the full connected component reachable from the node in either direction.

## Parameters

- **p** (`Pipeline`): The pipeline.

- **name** (`String`): The name of the target node.


## Returns

A new pipeline with the full connected component.

## Examples

```t
p |> subgraph("model_r")
```

## See Also

[downstream_of](downstream_of.html), [upstream_of](upstream_of.html)



# FILE: docs/reference/substring.md

# str_substring

Extract substring

Returns the part of the string between `start` and `end` indices.

## Parameters

- **s** (`String`): The input string.
- **start** (`Int`): The starting index (inclusive).
- **end** (`Int`): The ending index (exclusive).

## Returns:

Returns: The extracted substring.



# FILE: docs/reference/summarize.md

# summarize

Summarize data

Aggregates a DataFrame to a single row (or one row per group).

## Parameters

- **df** (`DataFrame`): The input DataFrame.

- **...** (`KeywordArgs`): Aggregations as name = expression pairs.


## Returns

The summarized DataFrame.

## Examples

```t
summarize(mtcars, $mean_mpg = mean($mpg))
summarize(group_by(mtcars, $cyl), $mean_hp = mean($hp))
```

## See Also

[mutate](mutate.html), [group_by](group_by.html)



# FILE: docs/reference/summary.md

# summary

Model Summary

Returns a tidy summary DataFrame for native models.

## Parameters

- **model** (`Model`): The model object (e.g., from lm()).


## Returns

Tidy summary dictionary with `_tidy_df` and metadata.

## Examples

```t
s = summary(model)
coefficients = s._tidy_df
```

## See Also

[fit_stats](fit_stats.html), [lm](lm.html)



# FILE: docs/reference/sum.md

# sum

Sum of numeric values

Calculates the sum of values in a List or Vector.

## Parameters

- **x** (`List[Number]`): | Vector[Number] The collection to sum.

- **na_rm** (`Bool`): = false Remove NA values before summing.


## Returns

| NA The sum of values.

## Examples

```t
sum([1, 2, 3])
-- Returns = 6

sum([1, NA, 3], na_rm = true)
-- Returns = 4
```



# FILE: docs/reference/suppress_warnings.md

# suppress_warnings

Suppress Diagnostics for a Node

Silences all captured warnings for the current node in the console summary. Warnings remain accessible programmatically via `read_node()` or `read_pipeline()`. Use this to reduce noise from known warnings during data processing (e.g., NAs in filter).

## Parameters

- **value** (`Any`): The value or expression to wrap. Usually call it at the end of a node definition.


## Returns

The original value, signaling the evaluator to suppress diagnostic output.



# FILE: docs/reference/swap.md

# swap

Swap a Pipeline Node Implementation

Replaces a node's implementation with a new node value. The dependency edges of the replaced node are preserved — this operation only changes the node's command and metadata. Use `rewire` to change dependencies.

## Parameters

- **p** (`Pipeline`): The pipeline.

- **name** (`String`): The name of the node to replace.

- **new_node** (`Node`): The new node implementation.


## Returns

A new pipeline with the node replaced.

## Examples

```t
p |> swap("model_r", node(command = <{ lm(y ~ x, data) }>, runtime = R))
```

## See Also

[patch](patch.html), [rename_node](rename_node.html), [rewire](rewire.html)



# FILE: docs/reference/sym.md

# sym

Convert a string to a Symbol

Creates a Symbol from a string so it can be injected into quoted code with `!!`. Existing Symbol values pass through unchanged.

## Parameters

- **x** (`String | Symbol`): The name to convert.


## Returns

The resulting symbol.

## Examples

```t
sym("mpg")
expr(select(df, !!sym("mpg")))
```


# FILE: docs/reference/tail.md

# tail

Get the last n rows/items

Returns the last n items from a List, Vector, or DataFrame. For DataFrames, it returns the bottom n rows.

## Parameters

- **data** (`DataFrame`): | List | Vector The collection to slice.

- **n** (`Int`): = 5 Number of items to return.


## Returns

| List | Vector A subset of the input containing the last n items.

## Examples

```t
tail([1, 2, 3, 4, 5, 6], n = 3)
-- Returns = [4, 5, 6]

df |> tail(n = 10)
```



# FILE: docs/reference/tanh.md

# tanh

Hyperbolic tangent

Compute hyperbolic tangent.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/tan.md

# tan

Tangent

Compute tangent (radians).

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/t_doc.md

# t_doc

Generate Documentation

Documentation tools. Call with "parse" to extract docs from `src/`, or "generate" to output markdown files to `docs/reference/`.

## Parameters

- **command** (`String`): Either "parse" or "generate".


## Returns



## Examples

```t
t_doc("parse")
t_doc("generate")
```



# FILE: docs/reference/t_make.md

# t_make

Build Pipeline Internally

Builds the `src/pipeline.t` pipeline entrypoint.

`src/pipeline.t` must call `populate_pipeline(...)` or `build_pipeline(...)`.
If it only calls `populate_pipeline(...)` without `build = true`, `t_make()`
emits a warning and continues after populating the pipeline.

## Parameters

- **filename** (`String`): (Optional) The pipeline build script path. Must be `src/pipeline.t`.


# FILE: docs/reference/to_array.md

# to_array

Convert to NDArray

Converts numeric columns of a DataFrame to a matrix (NDArray).

## Parameters

- **df** (`DataFrame`): The input DataFrame.

- **cols** (`List[Symbol|String]`): (Optional) Columns to include. Defaults to all numeric.


## Returns

A 2D array of the data.

## Examples

```t
mat = to_array(mtcars)
mat = to_array(mtcars, [$mpg, $wt])
```

## See Also

[dataframe](dataframe.html)



# FILE: docs/reference/today.md

# today

Get the current date

Returns the current local date as a Date value.



# FILE: docs/reference/to_float.md

# to_float

Convert to Float

Coerces a value to a float robustly. Handles strings with spaces, percentages, commas, and recognizes 'TRUE'/'FALSE'.

## Parameters

- **x** (`Any`): The value to convert.


## Returns

| NA The converted float.

## Examples

```t
to_float("3,14")
to_float("15%")
to_float(42)
```



# FILE: docs/reference/to_integer.md

# to_integer

Convert to Integer

Coerces a value to an integer robustly. Handles strings with spaces, percentages, commas, and recognizes 'TRUE'/'FALSE'.

## Parameters

- **x** (`Any`): The value to convert.


## Returns

| NA The converted integer.

## Examples

```t
to_integer("12 300")
to_integer("TRUE")
to_integer(3.14)
```



# FILE: docs/reference/to_lower.md

# to_lower

Convert to lowercase

Converts all characters in the string to lowercase.

## Parameters

- **s** (`String`): The string to convert.


## Returns

The lowercase string.



# FILE: docs/reference/to_numeric.md

# to_numeric

Convert to Numeric

Alias for `to_float`. Coerces a value to a numeric (float) robustly.

## Parameters

- **x** (`Any`): The value to convert.


## Returns

| NA The converted float.



# FILE: docs/reference/to_upper.md

# to_upper

Convert to uppercase

Converts all characters in the string to uppercase.

## Parameters

- **s** (`String`): The string to convert.


## Returns

The uppercase string.



# FILE: docs/reference/trace_nodes.md

# trace_nodes

Trace Pipeline Nodes

Prints a visual dependency tree of the pipeline nodes.

## Parameters

- **p** (`Pipeline`): The pipeline to inspect.

- **name** (`String`): (Optional) A specific node's name to trace.

- **transitive** (`Bool`): (Optional) If true, mark transitive dependencies with '*'.


## Returns

Returns invisibly. Prints to the console.

## Examples

```t
p = pipeline { x = 1; y = x + 1 }
trace_nodes(p)
trace_nodes(p, "y")
```



# FILE: docs/reference/transpose.md

# transpose

Transpose matrix

Returns the transpose of a 2D NDArray.

## Parameters

- **matrix** (`NDArray`): The matrix to transpose.


## Returns

The transposed matrix.



# FILE: docs/reference/t_read_json.md

# t_read_json

Read Value from JSON

Deserializes a T value from a JSON file. Automatically handles type conversion for scalars, lists, and dictionaries.

## Parameters

- **path** (`String`): Path to the JSON file.


## Returns

The deserialized value.



# FILE: docs/reference/t_read_onnx.md

# t_read_onnx

Read an ONNX model file

Loads an ONNX model file from disk and returns a model dictionary. The resulting dictionary contains the model type identifier (^onnx), the file path, input/output names, and model-level metadata. This model object can be passed to `predict()` for native T-side inference.

## Parameters

- **path** (`String`): The file path to the .onnx model.


## Returns

A model dictionary containing:



# FILE: docs/reference/t_read_pmml.md

# t_read_pmml

Read a PMML model file

Loads a PMML file from disk and returns its parsed model representation.



# FILE: docs/reference/trim_end.md

# trim_end

Trim trailing whitespace

## Parameters

- **s** (`String`): 


## Returns





# FILE: docs/reference/trimmed_mean.md

# trimmed_mean

Trimmed mean

Compute mean after trimming both tails by fraction.

## Parameters

- **x** (`Vector`): | List Numeric input.

- **trim** (`Float`): Trim proportion in [0, 0.5).


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/trim_start.md

# trim_start

Trim leading whitespace

## Parameters

- **s** (`String`): 


## Returns





# FILE: docs/reference/trunc.md

# trunc

Truncate values

Truncate fractional component toward zero.

## Parameters

- **x** (`Number`): | Vector | NDArray Numeric input.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/t_run.md

# t_run

Run a T script

Evaluates a T script file and imports its definitions into the current environment. Useful for interactive development to reload module files.

## Parameters

- **filename** (`String`): The path to the T file to execute.


## Returns



## Examples

```t
t_run("src/my_script.t")
```



# FILE: docs/reference/t_test.md

# t_test

Run tests

Runs the test suite for the current package. Wraps the CLI `t test` command for use within the REPL.

## Returns

Returns NA on success, or an Error if tests fail.



# FILE: docs/reference/t_write_json.md

# t_write_json

Write Value to JSON

Serializes a T value to a JSON file. This is used as the universal baseline for object transport between runtimes in the sandbox interchange protocol.

## Parameters

- **value** (`Any`): The value to serialize.

- **path** (`String`): Path to the destination file.


## Returns





# FILE: docs/reference/type.md

# type

Get the type name of a value

Returns a string representation of the value's type (e.g., "Int", "String", "List").

## Parameters

- **x** (`Any`): The value to inspect.


## Returns

The type name.

## Examples

```t
type(123)
-- Returns = "Int"

type([1, 2])
-- Returns = "List"
```



# FILE: docs/reference/tz.md

# tz

Extract the timezone label

Returns the timezone string attached to a Datetime value.



# FILE: docs/reference/uncount.md

# uncount

Expand rows by weight

Repeats each row according to a count column or weight expression.



# FILE: docs/reference/ungroup.md

# ungroup

Remove grouping

Removes the grouping structure from a DataFrame.

## Parameters

- **df** (`DataFrame`): The input DataFrame.


## Returns

An ungrouped DataFrame.

## Examples

```t
ungroup(df)
```

## See Also

[group_by](group_by.html)



# FILE: docs/reference/union.md

# union

Combine two pipelines

Returns a pipeline containing nodes from both inputs and errors on name collisions.



# FILE: docs/reference/unite.md

# unite

Combine multiple columns into one character column

unite() is a convenience function that pastes together multiple columns into a single character column.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **col** (`String`): The name of the new column to create.

- **...** (`Symbol`): The columns to combine (use $col syntax).

- **sep** (`String`): (Optional) Separator to use between values.

- **remove** (`Bool`): (Optional) If true, remove the input columns from the result.

- **na_rm** (`Bool`): (Optional) If true, missing values will be removed prior to uniting.


## Returns

The united DataFrame.

## Examples

```t
unite(df, "full_name", $first_name, $last_name, sep = " ")
```



# FILE: docs/reference/unknown.md

# unknown

Print Failed Node Logs

Prints stderr log sections for each failed node by resolving its derivation path through `nix log`.

## Parameters

- **drv_paths** (`Hashtbl`): Captured derivation paths keyed by node name.

- **errored** (`List[String]`): Node names that failed during the build.




# FILE: docs/reference/unnest.md

# unnest

Expand nested columns

Expands a nested list-column (produced by nest() or similar) back into its constituent rows and columns, effectively duplicating rows of the "parent" DataFrame for every row in the nested table.

## Parameters

- **df** (`DataFrame`): The DataFrame containing a nested column.

- **cols** (`Column`): Selection column to unnest (positional or 'cols=' arg).


## Returns

The expanded DataFrame.



# FILE: docs/reference/update_flake_lock.md

# update_flake_lock

Update Dependencies

Regenerates the `flake.nix` file from the current TOML configuration and runs `nix flake update` to lock dependencies to their latest versions within the specified tags.

## Returns

Ok(()) or an error message.



# FILE: docs/reference/upstream_of.md

# upstream_of

Extract Upstream Subgraph

Returns a new pipeline containing the named node and all of its transitive dependencies (ancestors in the DAG).

## Parameters

- **p** (`Pipeline`): The pipeline.

- **name** (`String`): The name of the target node.


## Returns

A new pipeline with only the node and its ancestors.

## Examples

```t
p |> upstream_of("predictions")
```

## See Also

[subgraph](subgraph.html), [downstream_of](downstream_of.html)



# FILE: docs/reference/var.md

# var

Variance

Compute sample variance.

## Parameters

- **x** (`Vector`): | List Numeric input.

- **na_rm** (`Bool`): = false Remove NA values first.


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/vcov.md

# vcov

Variance-Covariance Matrix

Returns the variance-covariance matrix of the model coefficients. For native T models, the full matrix is returned. For imported models, a diagonal matrix based on standard errors is returned as a fallback.

## Parameters

- **model** (`Model`): The model object.


## Returns

A square matrix representation with term names.

## Examples

```t
model = lm(mpg ~ wt, data = mtcars)
v = vcov(model)
```



# FILE: docs/reference/wald_test.md

# wald_test

Joint Wald Test

Tests a null hypothesis that a subset of coefficients are jointly equal to zero.

## Parameters

- **model** (`Model`): The model object.

- **terms** (`List[String]`): The coefficient names to test.

- **value** (`Float`): (Optional) The null value to test against. Defaults to 0.0.


## Returns

A one-row DataFrame with the test statistic and p-value.

## Examples

```t
wald_test(model, terms = ["wt", "hp"])
```



# FILE: docs/reference/wday.md

# wday

Extract or label the weekday

Returns weekday numbers, or weekday labels when requested, from Date or Datetime values.



# FILE: docs/reference/week.md

# week

Extract the week number

Returns the week number for Date or Datetime values.



# FILE: docs/reference/where.md

# where

Select columns by predicate

Selection helper that keeps columns for which a predicate function returns true.



# FILE: docs/reference/winsorize.md

# winsorize

Winsorize values

Clamp tails to specified quantile limits.

## Parameters

- **x** (`Vector`): | List Numeric input.

- **limits** (`Float`): | Vector[Float] One-sided or (lo, hi) limits in [0, 0.5).


## Returns

| Vector Computed result (scalar or vectorized).



# FILE: docs/reference/%within%.md

# %within%

Test interval membership

Returns true when a Date or Datetime value falls inside an interval.



# FILE: docs/reference/with_tz.md

# with_tz

Convert a datetime to a new timezone

Retains the instant in time while changing the displayed timezone label.



# FILE: docs/reference/write_arrow.md

# write_arrow

Write Arrow IPC file

Writes a DataFrame to an Apache Arrow IPC (Feather v2) file.

## Parameters

- **df** (`DataFrame`): The DataFrame to write.

- **path** (`String`): The output file path.


## Returns



## Examples

```t
write_arrow(df, "data.arrow")
```

## See Also

[read_arrow](read_arrow.html)



# FILE: docs/reference/write_csv.md

# write_csv

Write CSV file

Writes a DataFrame to a CSV file.

## Parameters

- **df** (`DataFrame`): The data to write.

- **path** (`String`): The output path.

- **separator** (`String`): (Optional) Field separator (default ",").


## Returns



## Examples

```t
write_csv(df, "output.csv")
```

## See Also

[read_csv](read_csv.html)



# FILE: docs/reference/write_registry.md

# write_registry

Registry Maintenance (Writer)

Writes a flat JSON object mapping node names to artifact paths.

## Parameters

- **path** (`String`): Destination file.

- **entries** (`List[(String,`): String)] Name-path pairs.


## Returns

String] Status.



# FILE: docs/reference/write_text.md

# write_text

Write text to a file

Writes a string to a file at the specified path.

## Parameters

- **path** (`String`): The file path.

- **content** (`String`): The content to write.


## Returns





# FILE: docs/reference/yday.md

# yday

Extract the day of year

Returns the day-of-year component from Date or Datetime values.



# FILE: docs/reference/year.md

# year

Extract the year component

Returns the calendar year from Date or Datetime values.



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


# FILE: docs/serializers.md

# Serializers in T

T uses a first-class serializer system to manage data interchange between different runtimes (T, R, Python, Julia) and for materializing pipeline nodes as persistent artifacts.

## 1. Using Serializers

Serializers are identified by the `^` prefix. You can specify them when defining pipeline nodes:

```t
p = pipeline {
  -- Use the built-in Arrow serializer for a DataFrame
  data = node(command = read_csv("large.csv"), serializer = ^arrow)
  
  -- Use the PMML serializer for a model
  model = rn(command = <{ lm(y ~ x, data = data) }>, serializer = ^pmml)
  
  -- Use the JSON serializer for a simple dictionary
  config = node(command = { "debug": true, "retries": 5 }, serializer = ^json)
}
```

### Implicit Serialization
If you don't specify a serializer, T uses the `^tlang` (internal binary) format for T-to-T communication. For other runtimes, T attempts to infer a sensible default based on the data type or the specific wrapper used (e.g., `shn()` defaults to `^text`).

## 2. Built-in Serializers

| Identifier | Name | Best For | Compatibility |
|---|---|---|---|
| `^tlang` | T-Native | T-to-T interchange | T only |
| `^arrow` | Apache Arrow | Large DataFrames | T, R, Python, Julia |
| `^pmml` | PMML | Predictive Models | T, R, Python |
| `^onnx` | ONNX | ML Models | T, R, Python |
| `^json` | JSON | Config, lists, dicts | T, R, Python |
| `^csv` | CSV | Tabular data | T, R, Python |
| `^text` | Plain Text | Logs, shell output | All |

## 3. The `serializer` Structure

A serializer is a first-class object in T. You can inspect its properties or even define your own.

```t
type serializer = {
  format: string,
  writer: function(path: string, value: any) -> result[NA, string],
  reader: function(path: string) -> result[any, string]
}
```

### Custom Serializers

You can create a custom serializer by defining a record that matches the required interface:

```t
my_log_serializer = {
  format: "log",
  writer: \(path, val) {
    -- custom logic to write log
    Ok(NA)
  },
  reader: \(path) {
    -- custom logic to read log
    Ok("log content")
  }
}

-- Usage
node(command = ..., serializer = my_log_serializer)
```

## 4. Static Coherence Checks

One of the most powerful features of T's serializer system is the **static coherence check**. When you build a pipeline, T verifies that the format produced by a source node matches the format expected by the consumer node.

```t
node A {
  target: wn("data.csv", serializer = ^csv)
}

node B {
  source: rn("data.csv", serializer = ^arrow)
}

-- Result: Static Error
-- "Format mismatch: Node A produces ^csv, but Node B expects ^arrow."
```

This prevents runtime errors after long-running computations by catching interchange mismatches at the start of the build.

## 5. Polyglot Support

For cross-language nodes, serializers provide the necessary glue code for the target runtime. For example, when using `^arrow` in an R node:

1. T injects the `arrow` R library into the build environment.
2. T generates the R code to call `arrow::write_ipc_file()`.
3. T ensures the resulting file is correctly tracked as a Nix artifact.

### Custom Polyglot Serializers: R and Python Snippets

For a serializer to work across non-T runtimes, it can optionally provide code snippets for R and Python. These snippets are strings that T injects into the generated build scripts.

You can define these by adding `r_writer`, `r_reader`, `py_writer`, or `py_reader` keys to your serializer dictionary. You can use standard strings or **foreign code blocks** `<{ ... }>` for better readability:

```t
my_custom_ser = [
  format: "custom",
  
  -- T implementation
  writer: \(path, val) { Ok(NA) },
  reader: \(path) { Ok(42) },
  
  -- R snippets (using foreign code blocks)
  r_writer: <{ function(obj, path) { saveRDS(obj, path) } }>,
  r_reader: <{ function(path) { readRDS(path) } }>,
  
  -- Python snippets
  py_writer: <{ lambda obj, path: pickle.dump(obj, open(path, 'wb')) }>,
  py_reader: <{ lambda path: pickle.load(open(path, 'rb')) }>
]
```

#### Injected Code Patterns

When T processes a node with an `R` runtime and the above serializer:
1. It looks for the `r_writer` snippet.
2. It generates a call in the node's R script: `<r_writer>(node_result, "artifact_path")`.

#### Registering Custom Formats

If you use a custom format name (e.g., `format: "myformat"`), you should ensure that your R or Python scripts have the necessary libraries loaded to handle that format. You can do this by adding the libraries to your `tproject.toml` or using the `functions` / `includes` parameters in the node definition.

For more information on how pipelines use these serializers, see the [Pipeline Tutorial](pipeline_tutorial.md). For a model-focused walkthrough of `^pmml`, see the [PMML Tutorial](pmml_tutorial.md).


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


# FILE: docs/type-system.md

# Type System

T currently has an **alpha-stage, mode-aware type system**. The implementation focuses on typed lambda signatures and strict validation for top-level functions, with broader static typing features planned for later phases.

## Why this exists

The typing design in `spec_files/typing_system.md` sets a dual goal:

- keep REPL exploration lightweight,
- while making scripts and packages more explicit and safer.

PRs #83 and #84 introduced the first concrete implementation of that plan: typed lambda syntax, generic parameter declarations, and strict-mode validation behavior.

## Execution modes

Two checker modes are available:

- `repl`
- `strict`

### Current behavior

- `t repl` defaults to `repl` mode.
- `t run <file.t>` defaults to `strict` mode.
- `--mode repl|strict` can be used to override defaults.

In `strict` mode, only **top-level lambda assignments** are validated today.

## Lambda syntax

T supports both untyped and typed lambda forms.

### Untyped lambda

Body is any expression.

```t
add = \(x, y) x + y
```

### Typed lambda

Return type annotation is included inside the parameter parentheses.

```t
add_int = \(x: Int, y: Int -> Int) (x + y)
```

### Generic typed lambda

Generic type variables must be declared explicitly with `<...>`.

```t
id = \<T>(x: T -> T) x
pair = \<A, B>(x: A, y: B -> Tuple[A, B]) [x, y]
```

## Type annotation forms currently parsed

### Base types

- `Int`
- `Float`
- `Bool`
- `String`
- `NA`

### Composite forms

- `List[T]`
- `Dict[K, V]`
- `Tuple[T1, T2, ...]`
- `DataFrame[SchemaLikeType]` (parsed as a type argument shape, not yet enforced semantically)

### Generic variables

Single uppercase identifiers are interpreted as type variables (for example `T`, `A`, `B`).

## What strict mode validates today

In `strict` mode, for top-level lambdas assigned with `name = \(...) ...`, T validates:

1. all parameters have type annotations,
2. return type is annotated,
3. if type variables are used, generic parameters are declared,
4. all used type variables are declared.

If any rule fails, evaluation is blocked with a type error.

## What is **not** implemented yet

The current implementation is intentionally narrow. The following items from the spec are still future work:

- full expression-level type inference (HM-style),
- end-to-end static typing of function application and operators,
- typeclass/constraint resolution,
- fully typed DataFrame schemas and column-level checks,
- typed AST pipeline stages beyond signature validation.

In other words, this is a **signature validation layer**, not yet a full static typechecker.

## Practical guidance

- Use `repl` mode for exploratory work.
- Use `strict` mode (default in `run`) for scripts and packages.
- Prefer explicit signatures on exported/top-level functions to make behavior auditable and future-proof as stricter checks are added.

## References

- Typing spec: `spec_files/typing_system.md`
- Initial implementation context: PR #83 and PR #84

---

## Next Steps

Now that you understand T's type system, head over to learn about the core execution model:

1. **[Pipeline Tutorial](pipeline_tutorial.md)** — Learn how to build reproducible, DAG-based data analysis workflows.
2. **[Data Manipulation Examples](data_manipulation_examples.md)** — Practical examples of data wrangling with T's core verbs.
