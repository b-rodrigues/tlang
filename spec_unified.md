# T Programming Language — Specification

> **Status**: Implementation-Driven Phase 1
> **Purpose**: A pragmatic, optionally-typed functional language for data analysis.
> **Inspiration**: R’s Tidyverse, Python’s readability, OCaml’s performance, Julia's ergonomics.

---

## ✨ Design Philosophy

*   **Data-Centric and Opinionated**: T is built specifically for data manipulation and analysis. Its core data structures and functions are designed to make common data-wrangling tasks expressive, safe, and fast.
*   **Declarative and Functional**: Focus on what to compute, not how. T avoids side effects and mutation in user code, leading to programs that are easier to reason about, parallelize, and debug.
*   **Pragmatic & Performant Backend**: T's standard library functions are thin, safe wrappers around high-performance OCaml libraries (like Owl for stats and Bigarray for numerics). It reuses battle-tested code instead of reinventing it.
*   **Gradual and Pragmatic**: The language provides a seamless path from simple, dynamic scripting in the REPL to building robust, statically-typed, and high-performance data pipelines.
*   **User-Centric Indexing**: The language is **1-indexed** to align with the conventions of modern data analysis (R, Julia) and natural human language.
*   **Reproducible by Design**: T uses Nix as its package manager, and every T project uses a Nix shell as its development environment, ensuring unparalleled reproducibility.

---

## 🔤 Syntax Overview

-   **Assignment**: `x = 3 + 4`
-   **Function Calls**: Supports positional (`f(1)`) and named (`f(x=1, y=2)`) arguments.
-   **Pipeline Operators**: T provides two pipes for chaining functions: the default conditional pipe `|>` and the unconditional "Maybe-Pipe" `?|>`.
-   **Lambdas**: `\(x) x * x`
-   **Data Structures**:
    -   `List`: `[1, "a", b: true]`
    -   `Dict`: `{name: "Alice", age: 30}`
    -   `Tensor`: `tensor([1, 2], [3, 4])`
-   **Dot access**: Works on named lists, dicts, and DataFrames — `x.a`, `df.name`.
-   **Missing Values**: `NA_int`, `NA_float`, `NA_string` (see Missing Data section).

---

## 📦 Built-in Data Types

T provides a rich set of data types, separating flexible general-purpose containers from high-performance ones.

#### General-Purpose Containers
-   **`List`**: An **ordered, heterogeneous** collection.
-   **`Dict`**: An **unordered, key-value map** with unique string keys.
-   **`String`**, **`Bool`**

#### High-Performance Containers
-   **`Tensor`**: A **homogeneous, N-dimensional numerical array** for mathematical computing, backed by OCaml's `Bigarray`.
-   **`DataFrame`**: A **2D table with heterogeneous column types**, composed of named, 1D vectors.
-   **`Factor`**: A memory-efficient type for categorical data with explicitly defined levels, crucial for statistical modeling.
-   **Concrete Numeric Types**: `Int8`, `Int16`, `Int32`, `Int64`, `Float32`, `Float64`.
-   *(Planned: `TimeSeries` and `Panel` DataFrame types for time-aware analysis.)*

#### Specialized Types
-   `Model`: An opaque object representing the result of a statistical model fit.
-   `Formula`: A first-class object representing a statistical formula (`y ~ x1 + x2`).
-   `Error`: A first-class, structured object representing a failure.
-   **`NA` values**: A rich system for typed and tagged missing values. T has **no `Null` type**.

---

## 📄 Example Programs

```t
-- Load a CSV file
people = read_csv("people.csv")

-- Select and filter with pipes
people
  |> select(name, age)
  |> filter(age > 30)
  |> mutate(group = if (age > 50) "senior" else "adult")

-- Define and use functions
square = \(x) x * x
map([1, 2, 3], square)

-- Dictionary
person = {name: "Alice", age: 30}
print(person.name)

-- Named list
x = [a: 1, b: 2]
print(x.a)

-- DataFrame column access
df.name
```

---

## 🔬 Scoping and Environments

T uses **lexical scoping**. The scope of a variable is determined by its location within the source code when a function is **defined**, not when it is **called**. Functions form **closures**, capturing the environment from where they were defined. Inner variables **shadow** outer variables without mutating them, ensuring functional purity.

---

## 💧 Missing Data Semantics

T has a powerful, first-class system for handling missing data, combining **Typed System NAs** and **Tagged User NAs**.
*   **Typed System NAs** (`NA_int`, `NA_float`, etc.) ensure type safety.
*   **Tagged User NA**s allow users to declare that specific values (e.g., `-99`) should be treated as missing, preserving metadata about *why* a value is missing (e.g., `define_missing(data, age, values = {-99: "Refused"})`).
*   A consistent set of predicates (`is_na`, `na_reason`) and function arguments (`na_rm`) allows for unified and expressive handling of both kinds of missingness.

---

## 🧪 Error Semantics & Pipeline Operators

T treats errors as first-class, inspectable objects and provides specialized pipe operators for robust control flow.

### Errors as First-Class Objects
When a function fails, it returns an `Error` object, which is a standard T `Dict` containing fields like `message`, `code`, `location`, and a `trace`. This allows for programmatic error handling using standard conditional logic and the `is_error()` predicate.

### Pipeline Operators: `|>` and `?|>`
1.  **The Conditional Pipe (`|>`):** This is the default, "happy path" operator. If the value on the left is an `Error` object, the pipeline **short-circuits**. Otherwise, the value is passed to the function on the right.

2.  **The Unconditional "Maybe-Pipe" (`?|>`):** This is the specialized operator for error handling. It **always** takes the value from the left—whether it is a success or an `Error`—and passes it to the function on the right.

---

## 🛡️ Gradual Type System

T features a **gradual type system** where safety is introduced incrementally through annotations. Code without annotations is fully dynamic. Adding a type annotation (`x: Int64 = ...`) creates a contract that is **verified at compile time** by a Hindley-Milner type inference engine.

---

## 🔧 Core Library and Data Model

### First-Class Formulas
R-style formulas (`y ~ x1 + x2`) are a first-class type. They are not just strings, but structured objects that can be programmatically manipulated and passed to modeling functions like `lm()`.

### Column Labels for Richer Output
Every column in a `DataFrame` can have an optional, human-readable **label** (e.g., `"GDP per Capita (2023 USD)"`) in addition to its programmatic **name** (`gdp_per_capita`). These labels are automatically used by output-oriented functions like `summary()` and future plotting packages.

### The Polymorphic `summary()` Function
The `summary(x, kind="default")` function is the primary tool for object inspection. When applied to a `Model` object, it produces `broom`-style tidy output as a `DataFrame`, controlled by the `kind` argument (`"tidy"`, `"glance"`, or `"augment"`).

---

## 🧩 Packages and Extensibility

### Nix-Native Package Management
T does not have a custom package manager; instead, **Nix is the package manager**. It uses a central "registry flake" to manage a curated list of community packages, providing unparalleled reproducibility.

### Foreign Function Interface (FFI)
For maximum performance, T provides an FFI for calling OCaml code directly, enabling power users to create their own compiled, high-speed extensions.

---

## 🚀 Production Workflows

### The Pipeline Engine
Idiomatic T code is structured as a **reproducible analytical pipeline**. T provides a set of REPL-based functions (`pipeline_load`, `pipeline_run`, `pipeline_get`) to manage a project defined as a Directed Acyclic Graph (DAG). This system uses **Dune** as its backend for parallel execution and persistent caching.

### The API Server
T includes a built-in mechanism for exposing functions as a high-performance web API. A `t serve` command parses an `api.t` file with special annotations (`@get /predict`) to launch a production-ready web server with auto-generated interactive documentation.

### Execution Model: A Hybrid Interpreter and Compiler (Long-Term Vision)
Initially an **AST-walking interpreter** for the REPL, T is designed to evolve into a hybrid system with an **optimizing compiler** and **bytecode Virtual Machine (VM)**. The `t` command-line tool will orchestrate this, allowing users to compile (`t compile`) and run (`t run`) files for maximum performance, while retaining the interpreter for interactive use.

---
---

# High-Level Implementation Roadmap

1.  **Phase 1: The Core Interpreter**
    *   Finalize the AST to support the rich `NA` system, error objects, column labels, factors, and formulas.
    *   Implement the `eval` module to handle all value types and the two pipe operators (`|>` and `?|>`).
    *   Implement the core package system and a basic `print`, `read_csv`, and `define_missing` function.
    *   Build a working REPL.

2.  **Phase 2: The Data & Stats Engine**
    *   Implement the `colcraft` package (`select`, `filter`, `mutate`, `set_labels`).
    *   Implement `Factor` creation and manipulation functions.
    *   Wrap the `Owl` library to implement the `stats` package, including `lm()` which accepts a `Formula` object and returns a `Model` object.
    *   Implement the powerful, polymorphic `summary()` function.

3.  **Phase 3: The Gradual Type System**
    *   Enhance the parser to fully parse type annotations.
    *   Build the `typechecker.ml` module with Hindley-Milner inference.
    *   Integrate the type checker into the compilation process.

4.  **Phase 4: The Production Engine**
    *   **Pipelines:** Implement the DAG parser, Dune generator, and `pipeline_*` functions.
    *   **API Server:** Add `Dream` dependency and implement the `t serve` command with annotation parsing and JSON serialization.

5.  **Phase 5: The Performance Overhaul (Long-Term)**
    *   Transition from an AST-walking interpreter to an optimizing compiler that generates bytecode for a high-speed Virtual Machine (VM), while retaining the interpreter for the REPL.

6.  **Future Considerations**
    *   First-class support for Time Series and Panel Data.
    *   A built-in testing framework (`t test`).
    *   A Quarto extension for reproducible reports.
