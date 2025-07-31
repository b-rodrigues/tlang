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
-   **Missing Values**: `NA_int`, `NA_float`, `NA_string` (see Missing Data section).
-   **Data Structures**:
    -   `List`: `[1, "a", NA_bool]`
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
-   **`DataFrame`**: A **2D table with heterogeneous column types**, composed of named, 1D vectors.
-   **Concrete Numeric Types**: `Int8`, `Int16`, `Int32`, `Int64`, `Float32`, `Float64`.

#### Special Values
-   `Model`: An opaque object representing the result of a statistical model fit.
-   `Error`: A first-class value representing a failure.
-   T has **no `Null` type**. It uses a sophisticated `NA` system for missing data (see below).

---

## 💧 Missing Data Semantics

T has a powerful, first-class system for handling missing data, designed for the realities of survey and observational data analysis. It combines two concepts: **Typed System NAs** and **Tagged User NAs**.

### 1. Typed System NAs
To maintain type safety, every core type has its own distinct `NA` representation. This prevents silent type coercion and ensures that operations on vectors containing missing values remain type-stable.
*   **Syntax**: `NA_int`, `NA_float`, `NA_string`, `NA_bool`.
*   **Behavior**: These values propagate through computations. For example, `5 + NA_int` results in `NA_int`.

### 2. Tagged User NAs
For survey data and legacy systems, users can declare that specific values within a vector should be treated as missing. This preserves crucial metadata about *why* a value is missing.
*   **Declaration**: A built-in function, `define_missing`, attaches this metadata to a DataFrame or vector.
    ```t
    # In a column of ages, -99 means the person refused to answer.
    my_data = my_data |> define_missing(age, values = {-99: "Refused"})
    ```
*   **Behavior**: By default, values like `-99` in the `age` column will now be treated as `NA` in all standard computations (`mean`, `sum`, etc.). The original value is preserved internally but masked during analysis.

### 3. Unified Behavior
The system provides a consistent way to work with both kinds of missingness.
*   **Predicates**:
    *   `is_na(x)`: Returns `true` for both System NAs and Tagged User NAs.
    *   `is_system_na(x)`: Returns `true` only for `NA_int`, `NA_string`, etc.
    *   `is_user_na(x)`: Returns `true` only for values that have been tagged as missing (e.g., `-99` in the example above).
    *   `na_reason(x)`: Returns the metadata string (e.g., `"Refused"`) for a tagged NA, or a system `NA` otherwise.
*   **Function Arguments**: Core analytical functions include arguments to control NA handling.
    *   `mean(x, na_rm = TRUE)`: The standard behavior to remove all `NA` values before computation.
    *   `mean(x, na_rm = TRUE, include_user_na = TRUE)`: An "escape hatch" to temporarily treat tagged values as their original numeric values for a specific calculation.

This hybrid system provides the type safety of R's `NA` system with the semantic richness of SPSS's user-missing values, offering a robust and expressive framework for real-world data cleaning and analysis.

---

## 🛡️ Gradual Type System

T features a **gradual type system** where safety is introduced incrementally through annotations.

*   **Core Principle**: Code without annotations is fully dynamic. Adding a type annotation (`x: Int64 = ...`) creates a contract that is **verified at compile time**.
*   **Type Inference**: The compiler uses Hindley-Milner type inference, meaning a few key annotations can allow the checker to infer types and catch errors throughout a large portion of the code.

---

## 🔧 Core Built-ins (Phase 1)

This is an illustrative, non-exhaustive list.

| Function | Description |
|---|---|
| `summary(x, kind="default")` | Provides a type-specific summary of any object. See below for model behavior. |
| `lm(data, formula)` | Fits a linear model, returning a `Model` object. |
| `read_csv(file, ...)` | Loads a CSV. The `col_types` argument allows for partial schemas. |
| `define_missing(data, ...)` | Defines tagged user-missing values on a vector or DataFrame column. |
| `is_na(x)`, `na_reason(x)` | Predicates for working with missing data. |
| `select()`, `filter()`, `mutate()` | Core `dplyr`-style data manipulation verbs. |

### The Polymorphic `summary()` Function

`summary()` is the primary tool for object inspection. When applied to a `Model` object, it produces `broom`-style tidy output.
*   `summary(my_model, kind="tidy")` (default): Returns a `DataFrame` of model components (coefficients, p-values, etc.).
*   `summary(my_model, kind="glance")`: Returns a single-row `DataFrame` of model fit statistics (R-squared, AIC, etc.).
*   `summary(my_model, kind="augment")`: Returns the original data augmented with observation-level statistics.

---

## 🧩 Packages and Extensibility

### Nix-Native Package Management
T does not have a custom package manager; instead, **Nix is the package manager**. It uses a central "registry flake" to manage a curated list of community packages, providing unparalleled reproducibility. Users declare dependencies in their project's `flake.nix`.

### Foreign Function Interface (FFI)
For maximum performance, T provides an FFI for calling OCaml code directly. This allows the standard library to be implemented in high-performance OCaml and enables power users to create their own compiled extensions.

---

## 🚀 Production Workflows

### The Pipeline Engine
Idiomatic T code is structured as a **reproducible analytical pipeline**. T provides a set of REPL-based functions (`pipeline_load`, `pipeline_run`, `pipeline_get`) to manage a project defined as a Directed Acyclic Graph (DAG). This system uses **Dune** as its backend for parallel execution and persistent caching.

### The API Server
T includes a built-in mechanism for exposing functions as a high-performance web API, inspired by FastAPI. A `t serve` command parses an `api.t` file with special annotations (`@get /predict`) to launch a production-ready web server with auto-generated interactive documentation.

---
---

# High-Level Implementation Roadmap

1.  **Phase 1: The Core Interpreter**
    *   Finalize the AST to support the rich `NA` system (replacing `VNull`) and typed/tagged metadata on vectors.
    *   Implement the `eval` module to handle all `V*` types and NA propagation rules.
    *   Implement the `read_csv` and `define_missing` functions as the core of the NA system.
    *   Build a working REPL.

2.  **Phase 2: The Data & Stats Engine**
    *   Implement the `colcraft` package (`select`, `filter`, `mutate`) ensuring all verbs correctly handle both System and Tagged NAs according to function arguments (`na_rm`, etc.).
    *   Wrap the `Owl` library to implement the `stats` package, including `lm()` which returns a `VModel` object.
    *   Implement the powerful, polymorphic `summary()` function.

3.  **Phase 3: The Gradual Type System**
    *   Enhance the parser to fully parse type annotations.
    *   Build the `typechecker.ml` module with Hindley-Milner inference.
    *   Integrate the type checker into the compilation process.

4.  **Phase 4: The Pipeline Engine**
    *   Implement the parser for `pipeline.t` files.
    *   Implement the Dune build plan generator.
    *   Implement the user-facing `pipeline_*` functions as REPL built-ins.

5.  **Phase 5: The API Server**
    *   Add the `Dream` web framework as a dependency.
    *   Extend the parser to recognize API annotations (`@get`, etc.).
    *   Implement the `t serve` command with dynamic route generation and JSON serialization.
