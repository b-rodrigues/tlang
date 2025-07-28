# T Programming Language — Phase 1 Specification

> **Status**: Very early stage, conceptual + implementation-driven  
> **Purpose**: Small declarative functional language for tabular data wrangling  
> **Inspiration**: R’s tidyverse, Python’s readability, OCaml’s performance

---

## ✨ Design Goals

- **Declarative**: Focus on what to compute, not how.
- **Functional**: No mutation or side effects in user code.
- **Data-centric**: Native support for tabular data (DataFrames).
- **Minimal**: Small, learnable surface.
- **Explicit error values**: Errors propagate as first-class values.
- **Composability**: Functions, pipelines, lambdas — all composable.
- **Interactive**: REPL-driven experience.
- **Hackable**: Packages live inside the repo, easy to contribute.

---

## 🔤 Syntax Overview

- **Assignment**: `x = 3 + 4` (no `let`)
- **Identifiers**: `a`, `name`, `total_price`
- **Strings**: `"hello world"`
- **Numbers**: `42`, `3.14`
- **Booleans**: `true`, `false`
- **Lambdas**: `\(x) x + 1`
- **Function definition**: `f = function(x, y, ...) (x + y)`
- **Function call**: `mean(x)`, `select(people, name)`
- **If expressions**: `if (x > 3) "big" else "small"`
- **List literals**: `[1, 2, 3]`
- **Named list elements**: `[a: 1, b: 2]`, accessible as `x.a`
- **Dict literals**: `{name: "Alice", age: 30}`
- **Dot access**: Works on named lists and DataFrames — `x.a`, `df.name`
- **List comprehension**: `[x * x for x in [1, 2, 3]]`
- **Pipe operator**: `x |> f` or `x |> f(a, b)`
- **Dots (`...`)**: For variadic arguments and forwarding

---

## 📦 Built-in Data Types

- `Number` (int or float)
- `String`
- `Bool`
- `List` of values (optionally named)
- `Dict` (Python-style)
- `DataFrame`
- `Error` values (e.g., `"file not found"`)

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

-- Using function with ...
plot = function(data, x, y, ...) (
  scatterplot(data, x = x, y = y, ...)
)

-- Function with standard notation
add = function(x, y) (x + y)

-- List comprehension
[x * x for x in [1, 2, 3]]

-- Dictionary
person = {name: "Alice", age: 30}
person.name

-- Named list
x = [a: 1, b: 2]
print(x.a)

-- DataFrame column access
df.name
```

---

## 🔧 Core Built-ins (Phase 1)

| Function           | Description                                |
|--------------------|--------------------------------------------|
| `read_csv(path)`   | Load CSV as DataFrame                      |
| `select(df, ...)`  | Select columns (NSE-like)                  |
| `filter(df, cond)` | Filter rows                                |
| `mutate(df, ...)`  | Add or transform columns                   |
| `mean(x)`          | Mean of list or DataFrame column           |
| `print(x)`         | Type-dispatched print                      |
| `map(list, f)`     | Apply function to list                     |
| `x |> f(...)`      | Pipe operator for chaining                 |

---

## 📝 Naming and Syntax Rules

- **Variable names**:
  - Can include letters, numbers, and underscores.
  - Cannot start with a number or reserved symbol.
  - Reserved symbols include: `=`, `+`, `-`, `*`, `/`, `|>`, `->`, etc.
  - To use *any* name (including spaces, numbers first, or symbols), wrap it in backticks:
    - Example: `` `hello world!` = 3 `` is legal.

- **Type annotations (optional)**:
  - Syntax: `x: Number = 3`
  - Functions: `f: (String, Number) -> Bool = function(name, age) (...)`
  - Type annotations are optional and ignored for now (parsed but not enforced).

- **Strings**:
  - Single quotes: `'hello'`
  - Double quotes: `"world"`
  - Triple quotes for multi-line strings (like Python):
    - `'''This is a\nmulti-line\nstring'''`
    - `"""Another\none"""`

```t
-- Examples
x = 3
long_name_2 = 42
`123number` = 1
`column with spaces` = 7

msg = '''This is
a long string'''
```

---

## 🧩 Packages (autoloaded at REPL startup)

- `core`: Functional primitives like `map`, `fold`, `filter`
- `stats`: Statistical functions like `mean`, `sd`
- `colcraft`: Data verbs like `select`, `filter`, `mutate` (renamed from `dplyr`)

Other packages can be added but must be explicitly loaded.

---

## 🚫 What’s Out of Scope (For Now)

- No mutation or assignments after `x = ...`
- No user-defined types yet (except via packages)
- No package registry (everything lives in repo)
- No macros or JIT (planned for later)

---

## 🧪 Error Semantics

All failed operations return a value of type `Error`, e.g.:

```t
x = read_csv("missing.csv")
print(x) -- prints: Error("file not found")
```

No exceptions — everything is a value.

---

## 🚀 Long-Term Vision: The Project as a DAG

While Phase 1 focuses on a REPL-driven, script-based workflow, the long-term vision for T is to treat entire projects as a **Directed Acyclic Graph (DAG)** of computational nodes. This elevates T from a scripting language to a declarative pipeline framework, inspired by tools like Dagster and Airflow, but deeply integrated into the language itself.

### Core Concepts

*   **Node**: A single, named computational step in the pipeline. Each node is defined by a T expression and produces a single output value (e.g., a DataFrame, a plot, a statistical model).
*   **Edge**: A dependency between nodes. If Node `B` requires the output of Node `A` as its input, there is a directed edge from `A` to `B`.
*   **Graph**: A project is defined by a file that describes the collection of all nodes and their dependencies. This graph must be acyclic.
*   **Runner**: A specialized execution engine that analyzes the graph, determines the optimal execution order (via topological sort), and orchestrates the computation.

### Benefits of the DAG Model

1.  **Automatic Caching (Memoization)**: The runner can cache the output of every node. If a node's source code and the outputs of its dependencies have not changed, it does not need to be re-executed. This is a massive time-saver in data science workflows.
2.  **Parallel Execution**: The runner can identify independent branches of the DAG and execute them in parallel, dramatically speeding up complex pipelines.
3.  **Visualization and Introspection**: The project's structure can be visually rendered as a graph, making complex dependencies easy to understand. Users could inspect the output (the resulting value) of any intermediate node without running the entire pipeline.
4.  **Reproducibility**: The DAG provides a complete, explicit "recipe" for the project, ensuring that results are reproducible from start to finish.

### Proposed Syntax

To support this model, we could introduce a new top-level construct, perhaps a `pipeline` block. Inside this block, nodes are defined using standard T assignment syntax. Dependencies are **implicitly discovered** when a node's expression refers to another node by name.

**Example:**

Instead of a linear script like this:

```t
-- script.t
raw_data = read_csv("data.csv")
filtered = filter(raw_data, age > 30)
summarized = summarize(filtered, mean_age = mean(age))
print(summarized)
```

The project would be defined in a `pipeline.t` file like this:

```t
-- pipeline.t

pipeline my_project {
  -- Node 1: Load raw data. No dependencies.
  raw_data = {
    read_csv("data.csv")
  }

  -- Node 2: Filter the data. Implicitly depends on `raw_data`.
  filtered_data = {
    raw_data |> filter(age > 30)
  }

  -- Node 3: Create a summary. Implicitly depends on `filtered_data`.
  summary_stats = {
    filtered_data |> summarize(mean_age = mean(age), max_age = max(age))
  }

  -- Node 4: A separate, independent branch for analysis.
  -- This could run in parallel with `filtered_data` and `summary_stats`.
  column_names = {
    get_colnames(raw_data)
  }
}
```

### Impact on Implementation (Future Phase)

*   **T Language Core (`eval.ml`)**: The core T interpreter would remain largely the same. It would be invoked by the runner to execute the T expression inside a single node.
*   **The DAG Runner**: A new entry point (`runner.ml`) would be created. Its responsibilities would be:
    1.  Parse the `pipeline` definition file to build an in-memory graph structure.
    2.  Perform a topological sort on the graph to create a valid execution plan.
    3.  For each node in the plan:
        a. Check if a valid cache for this node exists. If so, load it.
        b. If not, inject the outputs of its dependencies (already computed) into the evaluation environment.
        c. Execute the node's T expression using the core evaluator.
        d. Save the resulting value to a cache (e.g., a file on disk).
*   **File Structure**: Projects would be organized around a central `pipeline.t` file rather than a single script.

This approach provides a clear and powerful path forward for T, enabling it to handle complex, real-world data science projects in a robust and efficient manner.

---

### 🔧 The T Pipeline Engine: A High-Level API for Dune

T will provide a dedicated command-line interface (CLI) to manage and execute analytical pipelines. This CLI acts as a high-level facade, translating user-friendly commands into a robust backend powered by the **Dune build system**. The user will only ever need to interact with `t`, never directly with the underlying Dune files, which are treated as an internal implementation detail.

**Core Workflow:**

1.  The user defines their entire analytical process in a single `pipeline.t` file.
2.  The user runs a high-level command, such as `t run` or `t viz`.
3.  The **T Runner** (the `t` executable) parses the `pipeline.t` file.
4.  It automatically generates a hidden build directory (e.g., `.t_cache/`).
5.  Inside this directory, it generates two key components:
    *   A `dune` file that declares each pipeline node as a `(rule)`.
    *   A set of "node runner" scripts or commands required by the Dune rules.
6.  The T Runner then invokes `dune build` within that directory, telling it which node (target) to build.
7.  Dune's scheduler takes over, executing nodes in parallel, using its cache to skip work, and ensuring correctness.

---

### The Generated Build Plan

For a `pipeline.t` file, the T Runner will generate a `dune` file where each node is a build rule.

**Example `pipeline.t` node:**
```t
  filtered_data = {
    raw_data |> filter(age > 30)
  }
```

**Corresponding auto-generated `dune` rule in `.t_cache/dune`:**
```dune
; This rule describes how to compute 'filtered_data'
(rule
 ; The target is the cached, serialized result of this node
 (target cache/filtered_data.bin)

 ; This node depends on the result of the 'raw_data' node
 (deps   cache/raw_data.bin)

 ; The action to perform if the target is missing or a dependency has changed
 (action
  (run t --internal-run-node %{deps} --output %{target})))
```

The `t --internal-run-node` command is a special, hidden mode of the T executable. It knows how to:
1.  Load dependency values from the input files (e.g., `cache/raw_data.bin`).
2.  Create an environment where `raw_data` is bound to the loaded value.
3.  Execute the specific expression `raw_data |> filter(age > 30)`.
4.  Serialize the result and save it to the output file (`cache/filtered_data.bin`).

---

### The High-Level CLI

The user experience will be defined by the following commands:

| Command                   | Description                                                                                                     | Behind the Scenes                                                                                    |
| ------------------------- | --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `t run [node_name]`       | **Executes the pipeline.** If `node_name` is given, runs until that node is built. If omitted, runs all nodes.     | Generates the Dune build plan and executes `dune build .t_cache/cache/[node_name].bin`.              |
| `t plan` or `t status`    | **Displays the pipeline plan.** Shows the list of nodes, their dependencies, and their current cache status (fresh/stale). | Parses `pipeline.t` and compares node hashes against the on-disk cache to determine status.      |
| `t viz`                   | **Visualizes the pipeline.** Generates a `pipeline.dot` file that can be rendered into an image of the DAG.      | Parses `pipeline.t` and uses `ocamlgraph` to emit a graph definition in the DOT language.            |
| `t clean [node_name]`     | **Clears the cache.** If `node_name` is given, cleans only that node and its dependents. If omitted, clears all. | Executes `dune clean` or selectively removes files from the `.t_cache/` directory.                   |
| `t get <node_name>`       | **Retrieves a node's output.** Runs the pipeline if needed, then prints the value of the specified node.          | Ensures the node is built via `t run`, then deserializes and prints the result from the cache file. |

This architecture provides the best of both worlds: a simple, domain-specific user experience for data analysts, and a powerful, industrial-grade build engine ensuring that pipelines are fast, correct, and reproducible.
---

## 🛤 Implementation Stack

- **Language**: OCaml
- **Lexer/Parser**: OCamllex + Menhir
- **Evaluation**: AST interpreter in `eval.ml`
- **REPL**: `repl.ml`
- **CSV I/O**: OCaml `csv` library
- **Packaging**: Nix flake, no external build tools
