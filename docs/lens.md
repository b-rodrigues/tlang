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
