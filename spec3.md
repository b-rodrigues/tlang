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

## 🔤 Syntax Overview

-   **Assignment**: `x = 3 + 4`
-   **Function Calls**: Supports positional (`f(1)`) and named (`f(x=1, y=2)`) arguments.
-   **Pipe Operator**: `x |> f` is syntactic sugar for `f(x)`.
-   **Lambdas**: `\(x) x * x`
-   **Data Structures**:
    -   `List`: `[1, "a", b: true]`
    -   `Dict`: `{name: "Alice", age: 30}`
    -   `Tensor`: `tensor([1, 2], [3, 4])`

---

## 📦 Data Types

T provides a rich set of data types, separating flexible general-purpose containers from high-performance ones.

#### General-Purpose Containers
-   **`List`**: An **ordered, heterogeneous** collection.
-   **`Dict`**: An **unordered, key-value map** with unique string keys.
-   **`String`**, **`Bool`**

#### High-Performance Containers
-   **`Tensor`**: A **homogeneous, N-dimensional numerical array** for mathematical computing, backed by OCaml's `Bigarray`.
-   **`DataFrame`**: A **2D table with heterogeneous column types**, composed of named, 1D vectors.
-   **Concrete Numeric Types**: `Int8`, `Int16`, `Int32`, `Int64`, `Float32`, `Float64`.

#### Special Values
-   `Model`: An opaque object representing the result of a statistical model fit.
-   `Error`: A first-class value representing a failure.
-   `Null`

---

## 🛡️ Gradual Type System

T features a **gradual type system** where safety is introduced incrementally through annotations.

*   **Core Principle**: Code without annotations is fully dynamic. Adding a type annotation (`x: Int64 = ...`) creates a contract that is **verified at compile time**.
*   **Type Inference**: The compiler uses Hindley-Milner type inference, meaning a few key annotations can allow the checker to infer types and catch errors throughout a large portion of the code.

---

## 🔧 Core Library and Polymorphism

T's library is built around powerful, polymorphic functions that adapt their behavior to the type of their input.

### The `summary()` Function

The `summary(x, kind="default")` function is the primary tool for object inspection.

*   **For a `DataFrame`**: `summary(my_df)` returns a new DataFrame with summary statistics for each column (mean, median, etc.).
*   **For a `Tensor` or `Vector`**: `summary(my_vec)` returns a `Dict` of statistical properties (`{mean: ..., sd: ...}`).
*   **For a `Model` object**: The `kind` argument is used to produce `broom`-style tidy output.
    *   `summary(my_model, kind="tidy")` (default): Returns a `DataFrame` of the model's components (coefficients, p-values, etc.).
    *   `summary(my_model, kind="glance")`: Returns a single-row `DataFrame` of the model's overall fit statistics (R-squared, AIC, etc.).
    *   `summary(my_model, kind="augment")`: Returns the original data augmented with observation-level statistics (residuals, fitted values).

### Other Core Functions

*   **`lm(data, formula)`**: Fits a linear model, wrapping a function from a statistical library like `Owl`. Returns a `Model` object.
*   **`read_csv(file, col_types={...})`**: Loads a CSV. The `col_types` argument is a `Dict` mapping column names to types, allowing for partial schemas where unspecified columns are type-inferred.
*   **`select()`, `filter()`, `mutate()`**: Core `dplyr`-style data manipulation verbs.

---

## 🧩 Packages and Extensibility

T's ecosystem is designed for stability, transparency, and performance.

### Nix-Native Package Management
T does not have a custom package manager; instead, **Nix is the package manager**.
1.  **Packages are Flakes**: Every T package is a Nix Flake in its own repository.
2.  **A Central Registry Flake**: An official registry flake discovers and provides known-good versions of community packages.
3.  **Project-Level Dependencies**: Users declare their dependencies in their project's `flake.nix`, and the T compiler automatically finds them via an environment variable (`T_PACKAGE_PATH`).

### Foreign Function Interface (FFI)
For maximum performance and extensibility, T provides an FFI for calling OCaml code directly.
*   **Mechanism**: A user can write an OCaml function that accepts and returns T `value` types. This function can then be wrapped in a `VBuiltin` and exposed to the T runtime.
*   **Use Case**: This allows the standard library to be implemented in high-performance OCaml and enables power users to create their own compiled, high-speed extensions.

---

## 🚀 Production Workflows

T is designed to move from analysis to production seamlessly.

### The Pipeline Engine
Idiomatic T code is structured as a **reproducible analytical pipeline**. T provides a set of REPL-based functions (`pipeline_load`, `pipeline_run`, `pipeline_get`) to manage a project defined as a Directed Acyclic Graph (DAG). This system uses **Dune** as its backend for parallel execution and persistent caching.

### The API Server
T includes a built-in mechanism for exposing functions as a high-performance web API, inspired by FastAPI and Plumber.
*   **Declarative Syntax**: A user annotates T functions in an `api.t` file to define routes, methods, and parameters.
    ```t
    --* @get /predict
    --* @param month: Int64
    let predict_sales = function(month) { ... }
    ```
*   **`t serve` command**: This command parses the `api.t` file and launches a production-ready web server (using OCaml's `Dream` library), which automatically handles JSON serialization.
*   **Automatic Documentation**: The server also auto-generates interactive API documentation (Swagger/OpenAPI) from the annotations.

---

## 🛤️ High-Level Implementation Roadmap

1.  **Phase 1: The Core Interpreter**
    *   Finalize the AST and Parser for all specified syntax (named args, etc.).
    *   Implement the `eval` module to handle all `V*` types, including the `Bigarray`-backed `VTensor` and `VDataFrame`.
    *   Implement the core package system and a basic `print` and `read_csv` function.
    *   Build a working REPL.

2.  **Phase 2: The Data & Stats Engine**
    *   Implement the `colcraft` package (`select`, `filter`, `mutate`).
    *   Wrap the `Owl` library to implement the `stats` package, including `lm()` which returns a `VModel` object.
    *   Implement the powerful, polymorphic `summary()` function as the primary tool for object inspection.

3.  **Phase 3: The Gradual Type System**
    *   Enhance the parser to fully parse type annotations.
    *   Build the `typechecker.ml` module with Hindley-Milner inference.
    *   Integrate the type checker into the compilation process, running it before the evaluator.

4.  **Phase 4: The Pipeline Engine**
    *   Implement the parser for `pipeline.t` files.
    *   Implement the Dune build plan generator.
    *   Implement the `t --internal-run-node` CLI command.
    *   Implement the user-facing `pipeline_*` functions as REPL built-ins.

5.  **Phase 5: The API Server**
    *   Add the `Dream` web framework as a dependency.
    *   Extend the parser to recognize API annotations (`@get`, etc.).
    *   Implement the `t serve` command, including the logic for dynamic route generation and JSON serialization.
    *   Implement the automatic OpenAPI documentation generation. 
