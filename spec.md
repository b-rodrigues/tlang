# T Programming Language

> **Status**: Early conceptual and implementation-driven phase
> **Purpose**: A concise, declarative functional language for tabular data wrangling
> **Inspiration**: R’s tidyverse, Python’s readability, OCaml’s performance

---

## ✨ Design Goals

- **Data-Centric and Opinionated**: T is purpose-built for data manipulation and
  analysis. Its core data structures and functions are crafted to make common
  data-wrangling tasks expressive, safe, and performant.
- **User-Centric Indexing**: T uses 1-based indexing, aligning with conventions
  in R and Julia and with natural human expectations, reducing cognitive load
  and off-by-one errors.
- **Declarative and Functional**: The language emphasizes specifying *what* to
  compute, not *how*. It avoids side effects and mutation in user code,
  resulting in programs that are easier to reason about, parallelize, and debug.
- **Vectorized Operations**: Functions operate on entire vectors or columns at
  once. For example, `sum(x)` computes the sum of all elements in `x` without
  explicit loops.
- **Explicit Error Values**: Functions that fail return structured `Error`
  objects rather than crashing or throwing hidden exceptions. These can be
  programmatically inspected and handled like any other data.
- **Composability**: Functions and pipe operators are designed for seamless
  composition, allowing complex analyses to be built from simple, reusable
  components.
- **Functional OOP**: Methods are implemented as generic functions, not object
  members (`summary(my_model)` instead of `my_model.summary()`), fostering
  composability and consistency.
- **Interactive**: T is optimized for use in a Read-Eval-Print Loop (REPL),
  facilitating rapid, iterative exploration with immediate feedback.
- **Gradual and Pragmatic**: The language remains as simple as possible,
  enabling a smooth transition from dynamic scripting in the REPL to robust,
  statically-typed, high-performance data pipelines.
- **Reproducibility by Design**: The entire toolchain, including dependencies
  and packages, is managed by Nix to ensure full reproducibility across
  environments.
- **Hackable and Transparent Core**: The standard library is modular and
  self-contained, encouraging users to read, understand, and contribute to the
  source.
- **Copyleft License**: T uses the EUPL, a strong copyleft license requiring
  derivative works—including those provided as a service—to remain open source,
  safeguarding community freedom.

---

## 🪄 Core Language & Ergonomics

- **First-Class Pattern Matching**: T will support a `match` expression for
  elegantly deconstructing complex data structures such as DataFrames and
  `Error` objects. This enables concise and safe alternatives to deeply nested
  `if/else` logic, improving code clarity and reliability.
- **Lenses for Immutable Updates**: A dedicated lens library will provide
  ergonomic, composable ways to "get" and "set" deeply nested values in
  immutable data structures. Lenses allow for concise, functional updates and
  queries without sacrificing immutability.
- **Transient Mutation**: The `transient` block enables high-performance,
  locally-scoped mutation on data structures, with compiler-guaranteed
  isolation. This approach offers the speed of imperative code while preserving
  the safety and predictability of functional style.

---

## 📦 Built-in Data Types

T distinguishes between flexible, general-purpose containers and
high-performance structures.

### General-Purpose Containers

- `List`: Ordered, heterogeneous collections.
- `Dict`: Unordered key-value maps with unique string keys.
- `String`, `Bool`

### High-Performance Containers

- `Tensor`: Homogeneous, N-dimensional numerical arrays (backed by OCaml's
  `Bigarray`).
- `DataFrame`: 2D tables with heterogeneous column types, comprising named 1D
  vectors. Each column supports an optional human-readable label, in addition to
  its programmatic name, and is backed by Apache Arrow.
- Numeric Types: `Int8`, `Int16`, `Int32`, `Int64`, `Float32`, `Float64`.

### Special Values

- `Formula`: R-style formulas (`y ~ x1 + x2`) as structured, first-class
  objects.
- `Model`: Opaque objects representing fitted statistical models.
- `Error`: Structured objects representing failures.
- `NA` values: Typed (`NA_int`) and user-defined tagged missing values. **No
  `Null` type exists in T.**
- **Factor**: A dedicated, memory-efficient type for categorical data,
  supporting explicitly ordered levels—essential for statistical modeling and
  visualization.
- **TimeSeries & Panel Data**: Specialized `TimeSeries` and `Panel` DataFrame
  types, which internally track structure to enable high-level operations like
  lagging, rolling windows, and intuitive time-based indexing.

---

## 🏷️ Next-Level Data Model (Inspired by Statistical Packages)

- **First-Class `Factor` Type**: A memory-efficient, categorical data type
  supporting ordered levels, crucial for modeling and plotting.
- **Value Labels System**: Enables attaching human-readable string labels to
  specific values within a vector (e.g., `1 = "Male"`, `2 = "Female"`). Value
  labels are automatically leveraged by summary and visualization functions.
- **First-Class Time Series & Panel Data**: `TimeSeries` and `Panel` DataFrame
  types are aware of their temporal or panel structure, supporting operations
  such as lag, lead, rolling windows, and time-aware joins and visualizations.

---

## 📄 Example Script

```t
# Load a CSV file
people = read_csv("people.csv")

# Select and filter with pipes
people |>
  select(name, age) |>
  filter(age > 30) |>
  mutate(group = if (age > 50) "senior" else "adult")

# Define and use functions
square = \(x) x * x
map([1, 2, 3], square)

# Using function with ...
plot = function(data, x, y, ...) (
  scatterplot(data, x = x, y = y, ...)
)

# Function with standard notation
add = function(x, y) (x + y)

# List comprehension
[x * x for x in [1, 2, 3]]

# Dictionary
person = {name: "Alice", age: 30}
person.name

# Named list
x = [a: 1, b: 2]
print(x.a)

# DataFrame column access
df.name
```

---

## 📈 Native Plotting: Grammar of Graphics Integration

T will feature first-class, native plotting capabilities inspired by the Grammar
of Graphics paradigm, as exemplified by tools like ggplot2 (R) and Vega-Lite.
This approach treats plots as composable, declarative specifications rather than
imperative drawing commands, enabling users to build complex,
publication-quality visualizations from simple, readable building blocks.

### Core Principles

- **Declarative Specification**: Plots are constructed by declaring mappings
  between data variables and visual properties (aesthetics) such as position,
  color, size, and shape.
- **Layered Composition**: Visualizations are built by adding layers (e.g.,
  points, lines, bars) on top of a base plot, each with its own data mappings
  and geometric representation.
- **Separation of Concerns**: The data, visual mapping, and rendering details
  are kept separate, allowing users to focus on the "what" rather than the "how"
  of plotting.
- **Native DataFrame Interoperability**: Plots are created directly from T
  DataFrames and benefit from T's labeling, value labels, and type system for
  axes, legends, and tooltips.

### Example Syntax

```t
# Basic scatterplot
plot = ggplot(df, aes(x = height, y = weight)) |>
  geom_point(color = "blue") |>
  # Labels for axis are optional, as the ones defined
  # in the DataFrame object will be reused
  labs(title = "Height vs Weight", x = "Height (cm)", y = "Weight (kg)")

print(plot)

# Layered plot with regression line
ggplot(df, aes(x = age, y = cholesterol)) |>
  geom_point() |>
  geom_smooth(method = "lm", color = "red") |>
  labs(title = "Cholesterol by Age") |> print ()
```

### Features

- **Aesthetic Mapping**: The `aes()` function specifies which variables are
  mapped to which visual properties.
- **Geoms**: Built-in support for common geometric layers, including points,
  lines, bars, histograms, boxplots, and smoothers.
- **Faceting**: Native support for paneling by categorical variables (e.g.,
  `facet_wrap()` and `facet_grid()`).
- **Scales and Themes**: Customizable axis scales, color maps, legend placement,
  and overall plot appearance.
- **Labels and Value Labels**: Automatic use of column labels and value labels
  in axes and legends for more informative plots.
- **Interactive and Static Output**: Plots can be rendered as interactive
  HTML/SVG or exported as static images (PNG, PDF, SVG).

### Extensibility

- **Composable Layers**: Users can define their own geoms and statistical
  transformations, and contribute them as packages.
- **Integration with REPL and Quarto**: Plots can be displayed inline in the
  REPL and embedded directly in Quarto documents for reproducible reporting.

### Design Rationale

By natively integrating a grammar of graphics system, T ensures that data
visualization is as expressive, composable, and reproducible as the rest of the
language. This empowers users to move seamlessly from data wrangling to
insightful, publication-ready graphics in a single, unified workflow.

## 💧 Missing Data Semantics

T provides a robust, first-class missing data system, blending **Typed System
NAs** and **Tagged User NAs**.

### 1. Typed System NAs

Each core type has a unique `NA` variant, ensuring type safety and preventing
implicit coercion in vectors with missing data.

- **Syntax**: `NA_int`, `NA_float`, `NA_string`, `NA_bool`
- **Behavior**: These propagate through computations (e.g., `5 + NA_int` yields
  `NA_int`).

### 2. Tagged User NAs

Users may designate specific values as missing (e.g., survey codes like `-99`),
preserving metadata on *why* a value is missing.

- **Declaration**: Use `define_missing` to attach metadata.
    ```t
    my_data = my_data |> define_missing(age, values = {-99: "Refused"})
    ```
- **Behavior**: Tagged values are treated as `NA` in computations but retain
  original values internally.

### 3. Unified Behavior

T provides consistent handling for both missingness types.

- **Predicates**:
    - `is_na(x)`: True for both System and User NAs.
    - `is_system_na(x)`: True for system-level NAs.
    - `is_user_na(x)`: True for user-tagged NAs.
    - `na_reason(x)`: Returns the missingness reason or a default for system
      NAs.
- **Function Arguments**: Analytical functions accept NA-handling arguments,
  e.g.:
    - `mean(x, na_rm = TRUE)`
    - `mean(x, na_rm = TRUE, include_user_na = TRUE)`

This hybrid system combines R's type safety with SPSS’s semantic richness for
practical, real-world data cleaning.

---

## 🔤 Syntax Overview

- **Assignment**: `x = 3 + 4`
- **Identifiers**: `a`, `name`, `` `total price` ``
- **Strings**: `"hello world"`, `'hello world'`, `'''multi-line'''`
- **Numbers**: `42`, `3.14` (default to Int64, Float64)
- **Booleans**: `true`, `false`
- **Lambdas**: `\(x) x + 1`
- **Function Definitions**: `f = function(x, y) (x + y)`
- **Function Calls**: Supports positional and named arguments
- **If Expressions**: `if (x > 3) "big" else "small"`
- **Data Structures**:
    - Lists: `[1, "a", true]`
    - Named lists: `[a: 1, b: 2]` (access via `x.a`)
    - Dicts: `{name: "Alice", age: 30}`
    - Tensors: `tensor([1, 2], [3, 4])`
    - Dot access: `x.a`, `df.name`
- **List Comprehensions**: `[x * x for x in [1, 2, 3]]`
- **Pipe Operators**: `x |> f`, `x |> f(a, b)`, `x ?|> f`
- **Variadics**: `...` for variadic arguments and forwarding

---

## ➡️ Pipes: `|>` and `?|>`

T provides two explicit pipe operators:

1. **Conditional Pipe (`|>`)**: The default operator. If the left-hand value is
   an `Error`, the pipeline short-circuits, returning the error immediately;
   otherwise, it passes the value to the right-hand function.

    ```t
    result = read_csv("file.csv") |>
      clean_data() |>
      fit_model()
    ```

2. **Unconditional Pipe (`?|>`)**: Always forwards the left-hand value, whether
   it is an `Error` or not, to the right-hand function. Useful for explicit
   error handling.

    ```t
    final_output = result ?|>
      handle_error_and_return_default()
    ```

---

## Functional Object-Oriented Programming

T employs **Functional Object-Oriented Programming (OOP)**, inspired by R and
detailed in *Advanced R* by Hadley Wickham. Methods are implemented as
polymorphic generic functions rather than object members. For example,
`summary(my_dataframe)` and `summary(my_model)` invoke different methods, but
share a unified interface. This design promotes composability and separates data
from operations.

- **For `DataFrame`**: `summary(my_df)` returns summary statistics by column.
- **For `Tensor` or `Vector`**: Returns a `Dict` of statistical properties.
- **For `Model`**: The `kind` parameter selects output style:
    - `"tidy"`: Returns a DataFrame of model components (default).
    - `"glance"`: Single-row DataFrame of fit statistics.
    - `"augment"`: Original data augmented with model statistics.

---

## 🧵 String Interpolation

T supports string interpolation for concise and readable string formatting.
Interpolated expressions are enclosed in curly braces `{}` within string
literals prefixed with `f`. During evaluation, each expression inside `{}` is
replaced with its value.

**Syntax Example:**
```t
name = "Alice"
age = 30
print(f"Name: {name}, Age: {age}")
```

This prints:
```
Name: Alice, Age: 30
```

**Example with expressions:**
```t
x = 5
y = 7
print(f"Sum: {x + y}")
```

**Usage in error handling:**
```t
result = read_csv("missing.csv")
if is_error(result) {
  print("Operation failed!")
  print(f"Reason: {result.message}")
}
```

**Mixing Both in One Program:** You can use both types as needed:

```t
name = "Alice"
print("Curly braces: { }")      # Output: Curly braces: { }
print(f"Hello {name} and {{brackets}}!")  # Output: Hello Alice and {brackets}!
```

String interpolation eliminates the need for explicit concatenation or
formatting functions like `sprintf`, enabling clear and expressive code.

---

## 🧩 Packages and Extensibility

### Package Management via Nix

T leverages Nix for package management to ensure reproducibility and stability.

1. **Packages as Flakes**: Every T package is a Nix Flake in its own Git
   repository.
2. **Central Registry Flake**: T maintains a curated registry, discoverable via
   PRs.
3. **Project Dependencies**: Users define dependencies in their `flake.nix`;
   `nix develop` brings all packages into scope.

### User-Contributed Packages

- **Structure**: Packages are Git repositories containing `.t` files, organized
  by function.
- **Distribution**: Hosted independently; installation is via Nix flake inputs.
- **Documentation**: The `tdoc` tool parses roxygen-style comments and generates
  Markdown docs, accessible via `help(function_name)`.
- **Testing**: The `t test` command runs test scripts in `tests/`, using
  `assert_equal()` for validation.
- **Integrated Testing Framework**: T includes a simple, built-in testing
  framework, activated by the `t test` command, for writing and running unit
  tests on T functions and pipelines.
- **Quarto Extension**: T provides a dedicated engine for Quarto, enabling users
  to create dynamic, reproducible documents and reports by embedding executable
  T code blocks within Markdown files.

### Minimal Reinvention

T minimizes reinvention, reusing mature technologies such as Apache Arrow for
core data types and relying on the Arrow C GLib library via OCaml bindings.
Memory is managed through robust finalizer logic to ensure safety and prevent
leaks.

### Foreign Function Interface (FFI)

For performance and extensibility, T exposes an FFI for direct OCaml
integration. OCaml functions operating on T `value` types can be wrapped and
invoked as native T functions.

---

## 🔬 Scoping and Environments

T uses **lexical (static) scoping**: variable scope is determined at function
definition, not call time. Functions form closures, capturing their defining
environment.

**Example:**

```t
x = 10
f = \() x

g = \() {
  x = 20
  f()  # Uses x = 10
}

result = g()  # result == 10
```

**Variable Shadowing**: Inner scope variables override outer ones without
altering the outer value.

```t
name = "global"
my_function = \() {
  name = "local"
  print(name)
}
my_function()  # Prints "local"
print(name)    # Still "global"
```

This ensures functions do not create unintended side effects, in line with
functional programming best practices.

---

## 📝 Naming and Syntax Rules

- **Variable Names**: Letters, numbers, underscores; cannot start with a number
  or reserved symbol. Any name (including spaces or symbols) can be wrapped in
  backticks.
- **Type Annotations**: Optional and currently non-enforced; e.g., `x: Number =
  3`, `f: (String, Number) -> Bool = function(...)`
- **Strings**: Single, double, or triple quotes for multi-line.
- **Examples**:
    ```t
    x = 3
    long_name_2 = 42
    `123number` = 1
    `column with spaces` = 7
    msg = '''This is
    a long string'''
    ```

### Column Labels

Each DataFrame column may have an optional human-readable label, used in output
and visualization functions.

---

## The API Server

T includes a declarative mechanism for exposing functions as high-performance
web APIs, inspired by FastAPI and Plumber.

- **Syntax**: Annotate T functions in `api.t` to define routes and methods.
    ```t
    --* @get /predict
    --* @param month: Int64
    let predict_sales = function(month) { ... }
    ```
- **`t serve`**: Launches a web server using OCaml’s Dream library, with
  automatic JSON serialization and interactive documentation (Swagger/OpenAPI).

---

## 🛡️ Gradual Type System

T employs a **gradual type system**: unannotated code is dynamic, whereas type
annotations create statically checked contracts, verified at compile time.
Hindley-Milner inference enables type propagation from a small number of key
annotations.

---

## 📊 Advanced Modeling

- **First-Class Formulas**: R-style formulas (`y ~ x1 + x2`) are elevated to a
  first-class type, allowing them to be programmatically constructed, inspected,
  and passed to modeling functions.
- **Survey Design & Weighting Support**: T's ecosystem will include a dedicated
  library for complex survey data analysis, supporting the declaration of survey
  designs (stratification, clustering) and the application of sampling weights
  to all statistical computations, ensuring accurate inferences.

---

## Tooling

T provides an integrated suite of tools:

- **Language Server (`tls`)**: LSP implementation for live type checking,
  autocompletion (including DataFrame columns), documentation, and navigation.
- **Interactive Debugger**: REPL-based, supporting post-mortem analysis, call
  stack inspection, and stepwise execution.
- **Opinionated Formatter (`tfmt`)**: Ensures consistent code style across the
  ecosystem.

---

## 🧪 Error Semantics: Errors as First-Class Objects

Errors in T are structured, assignable, and inspectable data objects—not
exceptions. Failed functions return an `Error` object, represented as a
standardized `Dict` with fields:

- `message`: Human-readable explanation.
- `code`: Symbolic category (e.g., `#FileNotFound`, `#TypeError`).
- `location`: Optional file, line, and column data.
- `trace`: Optional call stack.
- `context`: Additional error-specific data.

Detection and handling use standard logic and the `is_error()` predicate.

```t
result = read_csv("missing.csv")
if is_error(result) {
  print("Operation failed!")
  print(f"Reason: {result.message}")
  if result.code == #FileNotFound {
    DataFrame()
  } else {
    result
  }
} else {
  result |> filter(age > 30)
}
```

Custom errors can be created using the built-in `error()` constructor.

---

## 🚀 Long-Term Vision: Projects as DAGs

Future phases will treat T projects as **Directed Acyclic Graphs (DAGs)** of
computational nodes, akin to Dagster or Airflow, but natively integrated.

### Core Concepts

- **Node**: A named computational step producing a single output.
- **Edge**: A dependency between nodes; edges define evaluation order.
- **Graph**: The set of all nodes and dependencies defined in a project file.
- **Runner**: Executes the graph in topological order, orchestrating
  computation.

### Benefits

- **Automatic Caching**: Nodes are cached and only recomputed if dependencies or
  code change.
- **Parallel Execution**: Independent branches run concurrently.
- **Visualization**: Projects can be rendered as graphs for clarity.
- **Reproducibility**: The DAG is an explicit recipe for reproducing results.

### Proposed Syntax

Instead of linear scripts:

```t
raw_data = read_csv("data.csv")
filtered = filter(raw_data, age > 30)
summarized = summarize(filtered, mean_age = mean(age))
print(summarized)
```

A `pipeline.t` file defines:

```t
pipeline my_project {
  raw_data = { read_csv("data.csv") }
  filtered_data = { raw_data |> filter(age > 30) }
  summary_stats = { filtered_data |> summarize(mean_age = mean(age), max_age = max(age)) }
  column_names = { get_colnames(raw_data) }
}
```

### Implementation (Future Phase)

- **Interpreter**: The core evaluator operates per node.
- **Runner**: Parses the pipeline, sorts nodes, checks caches, injects
  dependencies, and executes nodes.
- **File Structure**: Projects center around a `pipeline.t` file.

---

### 🔧 The T Pipeline Engine: Two-Layer Architecture

- **High-Level API**: REPL functions for pipeline loading, execution, status
  checking, result extraction, visualization, and cache cleaning.
- **Internal Runner**: CLI engine, invoked by the REPL functions, manages
  execution, caching, and result retrieval.

---

#### REPL-Based Pipeline Interaction

| T Function Signature | Description |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `pipeline_load(path: String) -> Pipeline` | Parses a `pipeline.t` file and returns a `Pipeline` object (no execution). |
| `pipeline_run(p: Pipeline, node: String)` | Executes the pipeline up to the specified node, returning status. |
| `pipeline_status(p: Pipeline)` | Returns the status of all nodes, including dependencies and cache status. |
| `pipeline_get(p: Pipeline, node: String)` | Ensures the node is built, then loads and returns its result in the REPL. |
| `pipeline_viz(p: Pipeline)` | Generates a DAG visualization (`pipeline.dot`) and returns the path. |
| `pipeline_clean(p: Pipeline, node: String)` | Clears cache for the specified node and its dependents. |

**Example REPL Workflow:**

```t
my_pipe = pipeline_load("project/pipeline.t")
pipeline_status(my_pipe)
pipeline_run(my_pipe, "summary_stats")
summary = pipeline_get(my_pipe, "summary_stats")
print(summary)
```

---

#### Wrappers and Internal Mechanics

REPL functions orchestrate calls to the CLI runner. For instance:

- `pipeline_run(p, "node")`: Executes `dune build .t_cache/cache/node.bin`
- `pipeline_get(p, "node")`: Triggers a build, then deserializes
  `.t_cache/cache/node.bin` and returns its value

This hybrid model provides an interactive, integrated experience atop a
parallel, caching backend.

---

### Execution Model: Hybrid Interpreter/Compiler (Vision)

T will evolve from an AST-walking interpreter (ideal for REPL and development)
to a hybrid system with an optimizing compiler and bytecode VM. The main `t`
command will support:

- `t`: Launches the REPL (interpreter mode)
- `t run <file.t>`: Runs a script via the interpreter
- `t compile <file.t>`: Produces bytecode (`file.tbc`)
- `t run <file.tbc>`: Executes compiled bytecode via the VM

This seamless workflow enables both interactive exploration and efficient
production execution, inspired by OCaml and similar languages.

---

## 🛤 Implementation Stack

- **Language**: OCaml
- **Lexing/Parsing**: OCamllex, Menhir
- **Evaluation**: AST interpreter in `eval.ml`
- **REPL**: `repl.ml`
- **I/O/DataFrames**: Apache Arrow
- **Pipeline engine**: Dune (Ocaml)
- **API Server**: Dream (OCaml)
- **Statistics**: Owl (OCaml)
- **Packaging**: Nix flakes only

---

# High-Level Implementation Roadmap


This roadmap outlines the phased development of T, balancing pragmatic
milestones with a vision for long-term innovation and extensibility.

---

The first 3 phases will focus on providing just enough of the core 
language, including the pipeline engine.

## **Phase 1: Core Interpreter and Language Primitives**

- **Abstract Syntax Tree (AST):** Finalize support for advanced constructs,
  including rich `NA` types, structured error objects, column labels, factors,
  and R-style formulas.
- **Evaluation Engine:** Implement the core `eval` module, supporting functional
  semantics and both conditional and unconditional pipe operators.
- **Essential Built-ins:** Provide foundational functions (`print`, `read_csv`,
  `define_missing`) and a minimal standard library.
- **REPL:** Deliver a robust, interactive Read-Eval-Print Loop for rapid
  prototyping and exploration.

---

## **Phase 2: Data Manipulation and Statistical Engine**

- **Columnar Data API:** Develop the `colcraft` package, offering idiomatic
  verbs for data wrangling (`select`, `filter`, `mutate`, `set_labels`).
- **Statistical Modeling:** Integrate the `Owl` OCaml library to deliver a
  barebones `stats` package, including linear modeling (`lm()`), summary
  statistics, and a generic `Model` type. This will be extended in a later phase.
- **Polymorphic Summaries:** Implement the generic `summary()` function for
  DataFrames, tensors, and models.
- **Factor and Value Label Support:** Provide native handling for categorical
  data and value labeling.

---

## **Phase 3: Production Pipeline Engine**

- **DAG Orchestration:** Implement parsing and execution of pipeline files as
  Directed Acyclic Graphs (DAGs), supporting caching, incremental builds, and
  parallel execution.
- **Build Integration:** Automate pipeline builds with Dune and manage
  computation outputs in a cache-aware manner.

---

## **Phase 4: Developer Experience and Ecosystem Tooling**

- **Package Ecosystem:**
    - Tooling for user-contributed packages with Nix flakes as first-class
      citizens.
    - `tdoc`: Extract and generate documentation from code comments.
    - `t test`: Built-in test runner for package/unit testing.
    - Flake scaffolding and management helpers.
- **Productivity Tools:**
    - `tls`: Language server with autocomplete, inline documentation, and
      column-aware suggestions.
    - Interactive Debugger: REPL-based, supporting breakpoints and call stack
      inspection.
    - `tfmt`: Opinionated code formatter for consistency across the ecosystem.

---

After Phase 4, a release announcement can be made, as there will be enough
of the language and tooling for others to easily contribute.

## **Phase 5: Native Visualization and extending Stats capabilities**

- **Enrich the Stats Module:** Extend the Stats module to integrate more of
  the `Owl` library.
- **Core Plotting Library:** Develop a native, grammar-of-graphics-inspired
  plotting system, enabling declarative, composable visualizations directly from
  T DataFrames.
- **Feature Set:** Support for layered plots, aesthetic mapping, faceting,
  theming, value label integration, and both static (PNG/PDF/SVG) and
  interactive (SVG/HTML) outputs.
- **REPL and Quarto Integration:** Inline visualization in the REPL and seamless
  embedding in Quarto documents for reproducible reports.

---

After Phase 5, a major version of the language should be released, perhaps version 0.5.

## **Phase 6: Gradual Type System and Static Analysis**

- **Type Annotations:** Extend syntax and parser to support optional type
  annotations.
- **Type Inference:** Implement Hindley-Milner-based inference in
  `typechecker.ml`.
- **Static Contracts:** Integrate the type checker into the build and REPL
  workflows, enabling a gradual transition from dynamic to statically-checked
  code.
- **Error Reporting:** Deliver clear, actionable static analysis and type error
  messages.

---

## **Phase 7: API Server**

- **API Exposure:** Develop annotation-based API exposure (`t serve`), with
  automatic OpenAPI/Swagger documentation and JSON serialization for DataFrames
  and models.

---

After Phase 7, version 1.0 of T could be released.

## **Phase 8: Performance Optimization and Compiler/VM Transition**

- **Optimizing Compiler:** Transition from AST interpretation to an optimizing
  compiler and bytecode VM for production workloads, while preserving the
  interpreter for interactive use.
- **JIT/Native Backends:** (Future) Explore Just-In-Time compilation and
  possible native code generation for critical paths.
- **Memory and Resource Management:** Refine memory management and finalization,
  especially for large data and streaming scenarios.

---

## **Phase 9: Extended Data and Modeling Support (Ongoing/Future)**

- **Time Series & Panel Data:** Introduce first-class support for time series
  and panel data structures, including period-aware indexing, rolling windows,
  and lag/lead operations.
- **Survey & Weighting:** Provide a comprehensive library for survey design,
  complex weighting, and stratification.
- **Geospatial Data:** Add spatial data types and geocomputation primitives.
- **Quarto and Reporting:** Deepen Quarto integration for literate programming
  and dynamic report generation.
- **Ecosystem Growth:** Support additional statistical, machine learning, and
  visualization packages through community contributions.

---

This roadmap is iterative and subject to refinement as the language and its
ecosystem evolve. Community feedback and contributions will inform
prioritization, with a focus on delivering robust, reproducible, and ergonomic
tools for modern data science.


# T’s performance: how to reach Ocaml speeds (implementation-ready map)

Below is a clear, implementable plan for making T pipelines execute with “compiled feel” 
by pushing work into Arrow/Owl while keeping a compact VM for orchestration. 
It’s written for engineers and LLMs who will implement the compiler, planner and runtime.

---

## Goal (one line)

Make common T pipelines (select / filter / mutate / group\_by / summarize / join / io) 
run as Arrow-native compute plans (zero-copy) and only call Owl (or other numeric kernels) 
for heavy numeric kernels — so pipelines execute close to native speed without requiring a full JIT up front.

---

# High-level architecture (layers)

1. **Parser → AST**
   T source → AST (NSE resolved where possible).
2. **Type/shape inference pass**
   Determine column types (arrow schema), shape (scalar/column/df), and whether an expression is column-vectorizable.
3. **Lowerer → IR (declarative operators)**
   Lower AST into a small set of declarative operators (logical plan): `Read`, `Project`, `Filter`, `Mutate(expr)`, `GroupBy(keys)`, `Aggregate(aggs)`, `Join`, `Write`.
4. **Optimizer / Planner**
   Transform logical plan: push filters, fuse adjacent mutates, detect vectorizable expressions, decide execution targets (Arrow kernel vs Owl vs VM).
5. **Physical plan**
   Plan = ordered physical operators with execution backends annotated per operator (Arrow kernel, Owl ndarray, VM bytecode, or JIT candidate).
6. **Executor**
   Runs the physical plan:

   * Arrow-backed operators call Arrow C compute kernels or C++ kernels via OCaml wrapper (zero-copy).
   * Owl-backed operators convert a column (zero-copy view when safe) to Owl ndarray, run numeric op, and convert results back to Arrow column.
   * VM bytecode executes orchestrating tasks, user-defined functions, or fallback ops.
   * JIT (optional later) compiles hot fused expressions to native code.

---

# Logical operators (the IR) — keep it tiny

Use this small set. Each maps to one or more physical implementations.

* `Read(path, format)` — returns DataFrame (Arrow table).
* `Project(df, [col...])` — select columns.
* `Filter(df, predicate_expr)` — predicate may be vectorizable.
* `Mutate(df, [(name, expr)...])` — add/replace columns.
* `GroupBy(df, [keys])` — returns grouped dataframe handle.
* `Aggregate(grouped_df, [(name, agg_expr)...])` — reduce per-group.
* `Join(left, right, on, kind)` — join two tables.
* `Write(df, path, format)` — write to disk.

Make each IR node carry schema and column-type metadata.

---

# Planner heuristics (rules to follow)

1. **Prefer Arrow native kernels** for:

   * Column selection, projection, slicing.
   * Vectorized arithmetic/boolean ops on fixed-width numeric columns.
   * Filter and comparison ops on fixed-width columns.
   * Aggregations for standard reductions (`sum`, `mean`, `min`, `max`, `count`) — use Arrow compute if available.

2. **Route to Owl when**:

   * Expression requires numeric libraries (linear algebra, advanced statistics).
   * Expression is supported in Owl but not Arrow (e.g., advanced ML routines).
   * Conversion should be zero-copy when column is fixed-width numeric; otherwise copy.

3. **Fallback to VM** for:

   * Arbitrary UDFs that are not vectorizable.
   * Row-wise operations that can’t be expressed as vector ops.
   * Small-data operations where the cost of kernel call overhead dominates.

4. **Fuse adjacent transforms** when possible:

   * `mutate(x = a + b); mutate(y = x * 2)` → fused single kernel computing `y` from `a,b`.
   * Implement fusion by building an expression graph per column and compiling it to a single Arrow compute kernel invocation or to a single Owl ndarray call.

5. **Group execution**:

   * If group-by cardinality is small relative to column length, execute group-aggs with Arrow (if available) or slice views + Owl operations per group.
   * Prefer Arrow group-aggregate kernels where provided.

6. **Zero-copy rule**:

   * If column is fixed-width primitive and memory is contiguous, create Owl view over Arrow buffer (no copy).
   * If not possible (nested/variable-length), copy or perform kernel in Arrow.

---

# Example: T pipeline → plan → execution

T code:

```t
let df = read_csv("data.csv")
let df2 = df
  |> select(name, age, salary)
  |> filter(age > 30 && salary > 50000)
  |> mutate(z = (salary - mean(salary)) / sd(salary))
  |> group_by(name)
  |> summarize(avg_z = mean(z), n = count())
```

Lowered logical plan (simplified):

1. `Read("data.csv")` schema: {name\:str, age\:int64, salary\:float64}
2. `Project([name, age, salary])`
3. `Filter(expr: age > 30 && salary > 50000)` — vectorizable
4. `Mutate(z = (salary - mean(salary)) / sd(salary))` — needs global mean/sd, vectorizable
5. `GroupBy([name])`
6. `Aggregate(avg_z = mean(z), n = count())`

Planner decision:

* Steps 1–4: Arrow-native kernels (CSV reader → Arrow Table; Project; Filter via Arrow compute kernels).
* `mean(salary)` / `sd(salary)`:

  * Compute global `mean` and `sd` with Arrow reduction kernels if available; otherwise use zero-copy Owl ndarray.
* `Mutate` compute: use fused vector expression executed as one Arrow compute kernel where possible, falling back to one zero-copy Owl call if Arrow lacks sd.
* `GroupBy` + `Aggregate`: use Arrow group-aggregate kernel for `mean` and `count` keyed by `name`. If Arrow group-agg not available for mean of derived column, compute `z` first and then group-agg with Arrow.

Execution notes:

* No per-row loops in VM.
* Data stays in Arrow memory; Owl sees buffer views only for numeric ops, and returns Arrow columns when done.

---

# Minimal physical operator API (OCaml-implementer view)

Expose these primitives in the OCaml runtime:

```ocaml
(* Arrow-backed *)
type arrow_table
val arrow_read_csv : string -> arrow_table
val arrow_project : arrow_table -> string list -> arrow_table
val arrow_filter : arrow_table -> predicate -> arrow_table
val arrow_mutate_vectorized : arrow_table -> (string * vector_expr) list -> arrow_table
val arrow_group_aggregate : arrow_table -> keys:string list -> aggs:(string * agg_expr) list -> arrow_table

(* Owl bridge *)
type ndarray_view  (* zero-copy view into Arrow buffer when possible *)
val arrow_col_as_ndarray_view : arrow_table -> col_name:string -> ndarray_view option
val owl_compute_ndarray : ndarray_view -> owl_op -> ndarray_view

(* Utilities *)
val column_is_fixed_width : arrow_table -> col_name -> bool
val column_buffer_ptr : arrow_table -> col_name -> (ptr, length)
```

Design the OCaml wrappers so the planner can request either Arrow kernel or Owl view; the wrappers handle ownership and safety.

---

# Bytecode VM — role and op set

The VM is small: orchestrator, control flow, UDFs, and fallback execution.

Essential op-categories:

* `LOAD_TABLE`, `PROJECT`, `BIND_COL` — high-level table ops that mostly call into Arrow.
* `CALL_ARROW_KERNEL kernel_id args -> table/col` — call pre-registered Arrow kernels.
* `CALL_OWL op args -> col` — call Owl operations on a provided view.
* `ITER_GROUPS` / `APPLY` — iterate groups when groupwise UDF required (should be avoided for heavy loops).
* `CALL_UDF` — run T-defined function row-wise (slow path).
* `JIT_HINT start_label end_label` — mark hot region for future JIT.

Keep bytecode compact and let planner emit `CALL_ARROW_KERNEL` rather than many small VM instructions.

---

# JIT strategy (phase 2, optional)

* Detect hot fused expressions (e.g., repeated `mutate` expressions) via `JIT_HINT`.
* Lower fused vector\_expr to LLVM IR or use MetaOCaml to generate OCaml that uses Arrow buffers/Owl views directly.
* Compile to a native function and replace the `CALL_ARROW_KERNEL`/`CALL_OWL` with direct native call.
* Keep JIT optional; initial system should perform very well without it because Arrow/Owl do the heavy work.

---

# LLM / implementer rules for lowering (explicit, machine-friendly)

1. Always preserve schema metadata at every pass.
2. Mark expressions as `VECTORIZABLE` only when:

   * They operate solely on fixed-width primitive columns, and
   * They use only elementwise arithmetic/boolean ops or reductions.
3. For `Mutate`:

   * Build expression DAG per new column.
   * Attempt to fuse nodes; if fused DAG fits Arrow compute kernel patterns, emit single `CALL_ARROW_KERNEL`.
4. For `GroupBy`:

   * If `Aggregate` uses only Arrow-supported aggs → plan `arrow_group_aggregate`.
   * Else if aggregation function is expressible as a combination of Arrow reductions → rewrite.
   * Else slice groups as views and route to Owl per-group (fallback).
5. For UDFs:

   * Try to convert UDF to vectorized form (map UDF over Arrow column as kernel). If not possible, fall back to VM row-wise apply and warn.
6. Always annotate physical plan nodes with `cost_estimate` (rows \* cost\_per\_row or kernel\_cost) for future planner improvements.

---

# Testing checklist (for correctness & speed)

* Unit tests for AST → IR lowering and NSE behavior.
* Property tests: apply pipeline to small dataset both in pure-VM and in planned Arrow/Owl execution; results must match elementwise.
* Zero-copy tests: ensure Owl view sees underlying buffer changes correctly; ensure memory safety when Arrow frees buffers.
* Performance benchmarks:

  * Single-column numeric arithmetic (1e7 rows).
  * Filter + project pipeline.
  * Group-by with many groups vs few groups.
  * Mutate involving mean/sd computed via Arrow vs via Owl view.
* Regression tests for fused vs unfused correctness.

---

# Prioritized implementation roadmap (short)

Phase A (MVP):

1. Parser, AST, NSE.
2. Arrow OCaml wrapper basics: read\_csv, project, filter, simple reduce (sum, mean).
3. Lowerer → logical IR and simple planner that maps to Arrow kernels or VM fallback.
4. REPL and pretty printing for Arrow tables.

Phase B (polish & numeric):

1. Owl bridge with zero-copy ndarray view.
2. Implement `mutate` fusion for arithmetic + mean/sd using Arrow or Owl.
3. Group-aggregate via Arrow; fallback per-group to Owl.

Phase C (performance & JIT):

1. Add cost-based planner improvements + more Arrow kernels.
2. Add `JIT_HINT` and implement simple JIT for fused expressions (optional).
3. Extensive benchmarks and native binaries.

---

# Quick implementation checklist for an LLM or contributor

* Keep IR small and typed.
* Always attach `schema` to nodes.
* Planner emits `CALL_ARROW_KERNEL` wherever possible; only emit row-wise UDFs when unavoidable.
* Implement Owl bridge as `arrow_col_as_ndarray_view` with a safe API to pin Arrow memory while Owl uses it.
* Add fusion pass that combines adjacent `Mutate` expressions into one vector\_expr graph.
