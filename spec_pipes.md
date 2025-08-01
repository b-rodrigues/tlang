

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
*   **Hackable and Transparent Core**: The language's standard library is organized into small, self-contained files (one per function), making it easy for users to read the source and contribute.

---

## 𔒷 Syntax Overview

-   **Assignment**: `x = 3 + 4`
-   **Function Calls**: Supports positional (`f(1)`) and named (`f(x=1, y=2)`) arguments.
-   **Pipeline Operators**: T provides two pipes for chaining functions: the default conditional pipe `|>` and the unconditional "Maybe-Pipe" `?|>`.
-   **Lambdas**: `\(x) x * x`
-   **Data Structures**:
    -   `List`: `[1, "a", b: true]`
    -   `Dict`: `{name: "Alice", age: 30}`
    -   `Tensor`: `tensor([1, 2], [3, 4])`

---

## 📦 Built-in Data Types

T provides a rich set of data types, separating flexible general-purpose containers from high-performance ones.

#### General-Purpose Containers
-   **`List`**: An **ordered, heterogeneous** collection.
-   **`Dict`**: An **unordered, key-value map** with unique string keys.
-   **`String`**, **`Bool`**

#### High-Performance Containers
-   **`Tensor`**: A **homogeneous, N-dimensional numerical array** for mathematical computing, backed by OCaml's `Bigarray`.
-   **`DataFrame`**: A **2D table with heterogeneous column types**, composed of named, 1D vectors. Each column can have an optional, human-readable **label** (for plots and tables) in addition to its programmatic **name**.
-   **Concrete Numeric Types**: `Int8`, `Int16`, `Int32`, `Int64`, `Float32`, `Float64`.

#### Special Values
-   `Model`: An opaque object representing the result of a statistical model fit.
-   `Error`: A first-class, structured object representing a failure.
-   **`NA` values**: A rich system for typed (`NA_int`) and tagged user-defined missing values. T has **no `Null` type**.

---

## 💧 Missing Data Semantics

T has a powerful, first-class system for handling missing data, designed for the realities of survey and observational data analysis. It combines **Typed System NAs** and **Tagged User NAs**.
*   **Typed System NAs** (`NA_int`, `NA_float`, etc.) ensure type safety.
*   **Tagged User NA**s allow users to declare that specific values (e.g., `-99`) should be treated as missing, preserving metadata about *why* a value is missing (e.g., `define_missing(data, age, values = {-99: "Refused"})`).
*   A consistent set of predicates (`is_na`, `na_reason`) and function arguments (`na_rm`) allows for unified and expressive handling of both kinds of missingness.

---

## 🧪 Error Semantics & Pipeline Operators

T treats errors as first-class, inspectable objects and provides specialized pipe operators for robust control flow.

### Errors as First-Class Objects
When a function fails, it returns an `Error` object, which is a standard T `Dict` containing fields like `message`, `code`, `location`, and a `trace`. This allows for programmatic error handling using standard conditional logic and the `is_error()` predicate.

### Pipeline Operators: `|>` and `?|>`
T provides two distinct pipe operators to handle different control-flow intents, ensuring that pipeline behavior is always explicit and predictable.

1.  **The Conditional Pipe (`|>`):** This is the default, "happy path" operator, designed for safety and readability. It inspects the value from its left-hand side. If the value is an `Error` object, the pipeline **short-circuits**, and the `Error` object is immediately returned as the final result. If the value is a success, it is passed to the function on the right. This is the primary operator used for chaining data transformations.

    ```t
    -- This pipeline will safely stop at the first step that fails.
    let result = read_csv("file.csv")
      |> clean_data()
      |> fit_model()
    ```

2.  **The Unconditional "Maybe-Pipe" (`?|>`):** This is the specialized operator for error handling and introspection. Its rule is simple: **always** take the value from the left-hand side—whether it is a success value or an `Error` object—and pass it as the first argument to the function on the right. It is used to explicitly pipe a potential `Error` into a handling function.

    ```t
    let final_output = result
      ?|> handle_error_and_return_default()
    ```

---

## 🛡️ Gradual Type System

T features a **gradual type system** where safety is introduced incrementally through annotations. Code without annotations is fully dynamic. Adding a type annotation (`x: Int64 = ...`) creates a contract that is **verified at compile time** by a Hindley-Milner type inference engine.

---

## 🔧 Core Library and Polymorphism

T's library is built around powerful, polymorphic functions that adapt their behavior to the type of their input. The `summary(x, kind="default")` function is the primary tool for object inspection. When applied to a `Model` object, it produces `broom`-style tidy output as a `DataFrame`, controlled by the `kind` argument (`"tidy"`, `"glance"`, or `"augment"`).

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
T includes a built-in mechanism for exposing functions as a high-performance web API. A `t serve` command parses an `api.t` file with special annotations (`@get /predict`) to launch a production-ready web server (using OCaml's `Dream` library) with auto-generated interactive documentation.

---
---

# High-Level Implementation Roadmap

1.  **Phase 1: The Core Interpreter**
    *   Finalize the AST to support the rich `NA` system, column labels, and error objects.
    *   Implement the `eval` module to handle all value types and the two pipe operators (`|>` and `?|>`).
    *   Implement the core package system, a basic `print`, `read_csv`, and `define_missing` function.
    *   Build a working REPL.

2.  **Phase 2: The Data & Stats Engine**
    *   Implement the `colcraft` package (`select`, `filter`, `mutate`, `set_labels`).
    *   Wrap the `Owl` library to implement the `stats` package, including `lm()` which returns a `Model` object.
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
