# T — Technical Presentation: DSL Design, Semantics, and Architecture

**An architectural and language-level presentation of the T Orchestration Engine.**

---

## 1. Executive Summary & Design Philosophy

**T** is an experimental, reproducibility-by-design domain-specific language (DSL) for polyglot data science. Rather than treating pipelines as external configuration artifacts (such as Makefiles, YAML definitions, or Python orchestration scripts), T models computation graphs as **first-class, typed program structures** with explicit dataflow, immutable semantics, and content-addressed outputs.

```
┌────────────────────────────────────────────────────────────────────────┐
│                          T Source Script (.t)                          │
│                                                                        │
│   p = pipeline {                                                       │
│     raw   = jln(command = <{ ... }>, serializer = ^ipc)                │
│     model = pyn(command = <{ ... }>, deserializer = [raw: ^ipc])       │
│     plot  = rn(command  = <{ ... }>, deserializer = [model: ^ipc])     │
│   }                                                                    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ↓
┌────────────────────────────────────────────────────────────────────────┐
│                        T Compiler & DAG Builder                        │
│                                                                        │
│   • Sub-second schema & DAG validation (t check --schema)              │
│   • Dependency cycle detection & serialization resolution              │
│   • Dynamic pattern branching (map_pattern, cross_pattern)             │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ↓
┌────────────────────────────────────────────────────────────────────────┐
│                     Hermetic Nix Execution Sandbox                     │
│                                                                        │
│  ┌───────────────────────┐ ┌───────────────────────┐ ┌───────────────┐ │
│  │   Julia Runtime Node  │ │   Python Runtime Node │ │   R Runtime   │ │
│  │  (Isolated Sandbox)   │ │  (Isolated Sandbox)   │ │   (Sandbox)   │ │
│  └───────────┬───────────┘ └───────────┬───────────┘ └───────┬───────┘ │
│              │                         │                     │         │
│              ▼                         ▼                     ▼         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │             Content-Addressed Nix Store (/nix/store/...)           │ │
│  │        Zero-Copy Apache Arrow IPC (^ipc) / ONNX (^onnx) / PMML    │ │
│  └───────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────┘
```

The language was developed to resolve a fundamental failure mode in contemporary quantitative research: **the polyglot seam**. Modern quantitative workflows require the complementary strengths of specialized ecosystems:
- **Julia** for high-performance numerical simulation, ODE solving, and intensive mathematical loops.
- **Python** for modern machine learning, deep neural networks, and specialized AI frameworks.
- **R** for econometrics, specialized survey statistics, and publication-grade visualization.

When unified through conventional approaches—such as in-process foreign function interfaces (`reticulate`, `PyCall`), ad-hoc shell scripts, or fat container images—these systems become fragile. Shared memory collisions, runtime thread contention, and unpinned transitive system libraries cause pipelines to degrade over time.

T elevates the polyglot boundary into a first-class language construct:
1. **Hermetic Sandboxing:** Each node executes in an isolated Nix environment pinned to exact software revisions and system libraries.
2. **Process Isolation & Memory Safety:** Foreign runtimes communicate across separate process boundaries via structured, high-throughput serializations (principally Apache Arrow IPC and ONNX).
3. **Functional Immutability:** The language eliminates side effects, mutable state, and unhandled runtime exceptions.
4. **Sub-Second Static Auditing:** Structural and column-level schema mismatches are diagnosed in milliseconds before Nix build sandboxes are ever spawned.

---

## 2. Language Semantics & Functional Core

T is implemented as an immutable, functional tree-walking interpreter in OCaml 5.x with a formal LR grammar (Menhir) and lexer (ocamllex). The core semantics are strictly functional:

### 2.1 Immutability and Environment Bindings

All variables in T are immutable bindings created with the `=` operator. Re-binding an existing identifier in the same scope requires explicit variable shadowing via the `:=` operator. Variables can be explicitly unbound using `rm()`:

```t
-- Immutable binding
x = 42

-- Overwriting requires explicit shadowing
x := 43

-- Variables can be explicitly removed from the environment
rm(x)
```

There are no unrestricted `while` or `for` loops in T. Iteration and collection transformations are expressed purely through functional higher-order combinators (`map`, `filter`, `fold`, `reduce`) or DAG-level branch expansions (`map_pattern`).

### 2.2 First-Class Errors and the Dual-Pipe Architecture

T completely eliminates raw runtime exceptions. Functions never throw uncaught exceptions; instead, failures return a first-class structured value of type `Error` (`VError` in the internal AST). Errors carry a structured diagnostic payload including error class, message, call site, and suggested remediation.

To control dataflow across potential failure boundaries, T introduces two complementary pipe operators:

```
Standard Pipe (|>)
   Value ─────────► [ Function ] ─────────► Result
   Error ─────────► (Short-Circuit) ──────► Error (Untouched)

Maybe-Pipe (?|>)
   Value ─────────► [ Function ] ─────────► Result
   Error ─────────► [ Handler  ] ─────────► Recovered / Handled
```

- **Linear Pipe (`|>`)**: Designed for deterministic transformation chains. If the input expression evaluates to an `Error`, the pipe short-circuits and forwards the `Error` without executing downstream functions:
  ```t
  -- If read_csv fails (e.g., file not found), filter and nrow are skipped
  read_csv("missing.csv") |> filter($age > 25) |> nrow
  ```

- **Maybe-Pipe (`?|>`)**: Designed for explicit error inspection, handling, and fallback recovery. It unconditionally passes the left-hand value—including `Error` instances—to the right-hand function:
  ```t
  -- Gracefully recover from missing data
  read_csv("dataset.csv") ?|> (\(res) if (is_error(res)) default_df else res)
  ```

### 2.3 Explicit Missingness (`NA`)

In accordance with strict safety principles, T rejects `null`. Missing data is represented exclusively by the typed `NA` sentinel (`VNA`), preserving R-style missing data semantics. Operations encountering `NA` values without explicit `na_rm = true` flags propagate missingness or return a descriptive `Error`, preventing silent corrupted calculations.

### 2.4 Block Quotation and Non-Standard Evaluation (NSE)

Foreign language execution blocks in T are syntactically captured using quotation delimiters `<{ ... }>`. Within quotation blocks, raw code is captured as an unevaluated expression tree, preserving literal formatting, whitespace, and embedded tokens for transmission to the respective runtime compiler:

```t
-- Foreign Julia computation captured as quoted AST
raw_data = jln(command = <{
  using DataFrames, Random
  Random.seed!(42)
  DataFrame(x = rand(100), y = rand(100))
}>, serializer = ^ipc)
```

Within native T expressions, non-standard evaluation allows column references via `$colname` symbols, compiling into verified columnar access against Arrow schema descriptors.

---

## 3. The Computation Graph (DAG) Model

In T, pipelines are not declarative configuration text; they are first-class language values constructed via the `pipeline { ... }` primitive.

### 3.1 Node Typings and Node Lifecycle

Nodes inside a pipeline represent computations in T, R (`rn`), Python (`pyn`), Julia (`jln`), or POSIX Shell (`shn`). Every node traverses two distinct phases:

1. **Unbuilt Node (`UnbuiltNode`)**: A declarative specification capturing:
   - Target runtime and command payload (quoted block or T expression).
   - Inbound dependencies (`deps`).
   - Output serializer (`serializer`).
   - Inbound deserializer bindings (`deserializer`).
   - Environment variables, system package requirements, and resource constraints.
2. **Computed Node (`ComputedNode`)**: An immutable artifact residing in the content-addressed Nix store (`/nix/store/<hash>-t-node-<name>`).

```t
p = pipeline {
  -- Native T node
  filtered = node(
    command = raw_data |> filter($score > 0.5),
    serializer = ^ipc
  )

  -- Python training node with explicit deserialization mapping
  model = pyn(
    command = <{
      from sklearn.ensemble import RandomForestRegressor
      rf = RandomForestRegressor(random_state=42).fit(filtered[['x']], filtered['y'])
      rf
    }>,
    deserializer = [filtered: ^ipc],
    serializer = ^onnx
  )
}
```

### 3.2 Dynamic Pattern Branching (`map_pattern` & `cross_pattern`)

When pipelines must scale across parameter grids, folds, or partitioned datasets, T avoids imperative node generation scripts. The DAG compiler supports declarative pattern expansion:

```t
p = pipeline {
  -- Dynamically fan-out a node across cross-validation folds or groups
  folds = map_pattern(split_data, \(fold) {
    pyn(
      command = <{ train_fold(fold) }>,
      deserializer = [fold: ^ipc]
    )
  })
}
```

Branches are compiled directly into the dependency graph before build execution, preserving static cycle detection and hermetic caching across every generated branch.

### 3.3 Static DAG Conditionals (`node_when` & `node_fork`)

To accommodate conditional pipelines (e.g., executing heavy training nodes only in production environments or when external flags are asserted), T provides static graph combinators:
- `node_when(condition, node_def)`: Conditionally excludes a node from the DAG during compilation if `condition` evaluates to `false`.
- `node_fork(cond1, node1, cond2, node2, ..., .default = node_default)`: Evaluates conditional guards to select exactly one active dependency branch.

Critically, conditionals are evaluated during pipeline compilation, ensuring that the resulting Nix dependency graph remains completely static, acyclic, and deterministic.

---

## 4. Inter-Process Communication & Serialization Architecture

The core technical differentiator of T's multi-language execution engine is the complete elimination of shared-memory in-process bindings. Foreign runtimes execute in separate operating system processes within isolated Nix sandboxes.

### 4.1 Apache Arrow IPC (`^ipc`)

For tabular data interchange between T, Julia, Python, and R, T relies on the Apache Arrow IPC stream format. Arrow provides a standardized columnar memory layout:
- **Zero-Copy Deserialization:** Arrays are mapped directly from storage into runtime memory buffers without field-by-field conversion.
- **Type Fidelity:** Floating-point numbers, 64-bit integers, booleans, timestamps, and string dictionaries retain identical types across Julia, Python, R, and T.
- **No Text Parsing Overhead:** Replaces slow, lossy intermediate CSV/JSON generation with binary stream serialization.

### 4.2 Native Model Scoring via Embedded PMML (`^pmml`)

One of T's unique architectural features is **zero-runtime model scoring**. When a statistical or machine learning model is trained in R or Python (such as generalized linear models, decision trees, random forests, XGBoost, or LightGBM), T can capture the model as a Predictive Model Markup Language (`^pmml`) artifact.

The T runtime embeds its own native OCaml PMML evaluation engine:
```t
p = pipeline {
  -- Train complex tree ensemble in Python
  model = pyn(
    command = <{
      from sklearn.ensemble import HistGradientBoostingRegressor
      from skl2pmml import sklearn2pmml, PMMLPipeline
      pipeline = PMMLPipeline([("regressor", HistGradientBoostingRegressor())])
      pipeline.fit(X, y)
      pipeline
    }>,
    serializer = ^pmml
  )

  -- Evaluate natively inside T: NO Python or R runtime needed!
  scored = node(
    command = new_data |> mutate($prediction = predict(new_data, model)),
    deserializer = [model: ^pmml]
  )
}
```

At prediction time, T evaluates the model natively inside its own process. The downstream prediction node does not spawn Python, load `scikit-learn`, or link CPython shared libraries, reducing runtime memory overhead and eliminating dependency drift at scoring time.

### 4.3 Open Neural Network Exchange (`^onnx`)

For deep neural networks and complex estimators, T supports `^onnx` serialization. Models trained in PyTorch, scikit-learn, or Julia's Flux can be serialized to ONNX format and evaluated by any other node supporting an ONNX runtime session, with T orchestrating model metadata and versioning across the graph.

---

## 5. Hermetic Nix Integration & Build Sandboxing

T's reproducibility guarantee is rooted in its mandatory coupling with the [Nix package manager](https://nixos.org).

### 5.1 The Nix Store as a Content-Addressed Cache

Every node in a pipeline compiles into a Nix derivation (`.drv`). The derivation captures:
- The exact hash of the node's command code and quotation AST.
- The content-addressed hashes of all upstream input artifacts.
- The exact Nix store paths of the runtime environments (e.g., Python 3.11 with scikit-learn 1.4.1, R 4.3 with ggplot2 3.5, Julia 1.10 with DataFrames 1.6).
- System-level shared libraries, compilers, BLAS/LAPACK implementations, and environment variables.

When `build_pipeline(p)` is invoked:
1. T computes the derivation hashes for each node in topological order.
2. If an identical derivation already exists in the local Nix store or binary cache, the build step is skipped entirely, and the existing artifact path is returned immediately.
3. If an input changes, only the invalidated downstream subgraph is rebuilt in an isolated, network-disabled Nix sandbox.

### 5.2 Determinism Across Machines

Unlike tools that rely on floating version tags or unpinned system libraries, T guarantees that an identical pipeline run on a different host, CI runner, or cloud environment executes against the exact same bit-level binary toolchain.

---

## 6. Graph Introspection & Verification Tools

T provides a suite of compiler-level introspection tools to inspect and verify computation graphs without executing full builds:

### 6.1 Sub-Second Diagnostic Checking (`t check`)

Before launching builds, developers and AI agents can validate pipelines using `t check`:

| Tier | Flag | Scope of Verification | Nix Execution? |
|---|---|---|:---:|
| **Tier 1: Structural** | `t check script.t` | DAG topology, syntax, unbound identifiers, dependency cycles | **No** (milliseconds) |
| **Tier 2: Schema** | `t check --schema script.t` | + Column-level schema tracking, Arrow data types, name references | **No** (milliseconds) |
| **Tier 3: Environment** | `t check --env script.t` | + Nix expressions, `tproject.toml` package consistency, lockfiles | **Yes** (eval only) |

When errors occur, `t check --json` emits structured diagnostics designed for automated parsing:

```json
{
  "error_class": "schema_mismatch",
  "node": { "id": "predictions", "lang": "python" },
  "message": "Column 'signal' not found in upstream node 'sim_data'. Did you mean 'sig'?",
  "caused_by": ["sim_data"],
  "suggested_fix": {
    "kind": "rename_column",
    "old_name": "signal",
    "new_name": "sig",
    "confidence": "high"
  }
}
```

The accompanying `t fix` engine can dry-run and apply high-confidence repairs automatically.

### 6.2 Deep Object Introspection (`explain()`)

Any runtime object, dataset, or pipeline node can be inspected via the built-in `explain()` primitive:

```t
explain(p.predictions)
```

`explain()` outputs full AST metadata, inbound and outbound dependency links, serialization formats, schema definitions, and content-addressed Nix store coordinates.

---

## 7. Advanced Functional Optics & Verification

### 7.1 Composable Lenses (`lens`)

To safely query and transform deeply nested immutable data structures (such as nested configuration dictionaries, pipeline metadata, or complex JSON trees), T incorporates functional lenses:

```t
import lens

-- Create composable optics
user_city_lens = lens_path(["user", "address", "city"])

-- Non-destructively read or update
city = lens_view(user_city_lens, state)
new_state = lens_set(user_city_lens, "Geneva", state)
```

Lenses guarantee that updates produce modified copies while preserving the immutability and provenance of the original structures.

### 7.2 Property-Based Testing (`propcraft`)

For mission-critical analytical libraries and statistical pipelines, the **`propcraft`** package introduces generative property-based testing. Rather than asserting isolated test cases, developers declare system invariants:

```t
set_seed(42)

-- Assert invariant across hundreds of generated pseudo-random DataFrames
assert(
  prop_for_all(
    prop_gen_df([col_int("age", min=18, max=90), col_float("score")]),
    \(df) df |> filter($age >= 18) |> nrow == nrow(df)
  )
)
```

On invariant failure, `propcraft` performs deterministic test-case shrinking to extract the minimal failing counterexample, ensuring that edge cases in data parsing or mathematical routines are identified reproducibly.

---

## 8. Summary Table: T Architectural Attributes

| Dimension | T Design Specification |
|---|---|
| **Host Language** | OCaml 5.x (compiled via Dune) |
| **Parsing & Grammar** | LR(1) via Menhir; lexical analysis via ocamllex |
| **Execution Model** | Tree-walking interpreter + Nix-sandboxed polyglot process runner |
| **Graph Model** | First-class, immutable directed acyclic graph (`pipeline { ... }`) |
| **Data Interchange** | Process-isolated Apache Arrow IPC (`^ipc`), ONNX (`^onnx`), PMML (`^pmml`) |
| **Error Handling** | First-class `Error` values; short-circuiting pipe `|>`, recovery pipe `?|>` |
| **State Semantics** | Strictly immutable bindings; explicit shadowing (`:=`); no uncontrolled loops |
| **Reproducibility Engine** | Content-addressed Nix store derivations; hermetic sandbox per node |
| **Verification Loop** | Millisecond static checks (`t check --schema`), structured JSON diagnostics, `t fix` |
