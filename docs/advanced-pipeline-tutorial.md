# Advanced Pipeline Tutorial

> Dynamic branching, node manipulation, pipeline composition, and beyond

This guide covers advanced pipeline features building on the fundamentals from the [Pipeline Tutorial](pipeline_tutorial.md). You should be familiar with basic pipeline concepts (nodes, dependencies, building, and inspecting) before diving in here.

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

## 18. Skipping Nodes

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

## 19. Node Metadata

> [↩ Quick Reference: Pipeline DAG Structure](#3-pipeline-function-quick-reference)

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
| `runtime` | String | `"T"`, `"R"`, `"Python"`, or `"Julia"` |
| `serializer` | String | e.g. `"default"`, `"pmml"` |
| `deserializer` | String | e.g. `"default"`, `"pmml"` |
| `noop` | Bool | Whether the node is a no-op |
| `deps` | String | Comma-separated dependency names |
| `depth` | Int | Topological depth (roots = 0) |
| `command_type` | String | `"command"` or `"script"` |

`pipeline_to_frame` is the foundation for inspection: you can use T's standard `filter`, `select`, and `arrange` verbs on the resulting DataFrame.

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

## 20. Environment Variables

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

## 21. Node-Level Operations (`_node` family)


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

## 22. Pipeline Manipulation for Data Scientists

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
  filtered = to_dataframe([[x: 1], [x: NA], [x: 3]]) 
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

The `○` symbol indicates a suppressed node. You can still access the underlying warning objects programmatically via `warning_msg()` or `read_pipeline()`.

```t
warning_msg(p.filtered)               -- Returns the warning message string
read_pipeline(p).diagnostics.summary  -- Summary counts
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

## 25. DAG-Aware Transformations

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

## 26. Pipeline Composition

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

### Meta-Pipelines (`pipeline_of`)

For larger projects, you can compose multiple pipelines into a higher-order DAG using the `pipeline_of` block. T-Lang natively understands and automatically flattens meta-pipelines at execution time, meaning you can pass them directly to built-in commands like `populate_pipeline()`, `read_node()`, `inspect_node()`, or `inspect_pipeline()`.

#### `pipeline_of` block

Defines a group of sub-pipelines. The nodes within the block bind identifiers to pipeline values.

```t
p_etl = pipeline {
  raw   = read_csv("data.csv")
  clean = raw |> filter($value > 0)
}

p_stats = pipeline {
  summary = etl.clean |> mean
}

-- Compose them into a higher-order DAG
meta = pipeline_of {
  etl   = p_etl
  stats = p_stats
}
```

#### Automatic Dependency Inference

T-Lang automatically analyzes cross-pipeline references in node expressions (such as referencing `etl.clean` in the `stats` pipeline) to infer the execution order between sub-pipelines. The flattening engine automatically wires the root nodes of a dependent sub-pipeline to depend on the terminal nodes of the pipeline it references.


#### Native Execution & Namespacing

When a meta-pipeline is populated, queried, or inspected, T-Lang automatically flattens it internally. Node names are automatically namespaced (e.g. `etl.raw`, `etl.clean`, `stats.summary`) to prevent namespace collisions, and all internal variable references are rewritten accordingly.

```t
pipeline_nodes(meta)
-- ["etl.raw", "etl.clean", "stats.summary"]

pipeline_deps(meta)
-- {`etl.raw`: [], `etl.clean`: ["etl.raw"], `stats.summary`: ["etl.clean"]}

-- You can build the entire meta-pipeline directly:
populate_pipeline(meta, build = true)

-- You can read individual nodes using nested dot notation:
res = read_node(meta.stats.summary)
```

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

### Parameterizing Pipelines (Templates via Lambdas)

Rather than introducing new complex constructs, T-Lang encourages parameterizing pipelines using standard lambdas. Since lambdas return values and pipelines are first-class values in T-Lang, you can define a lambda that takes configuration parameters and returns a pipeline.

#### Example

Here is a template lambda that takes a multiplier parameter and returns a pipeline with two nodes:

```t
make_pipeline = \(multiplier: Int -> Pipeline) pipeline {
  raw      = [1, 2, 3]
  computed = raw * multiplier
}

p1 = make_pipeline(10)
p2 = make_pipeline(20)
```

At execution time, outer variables (like `multiplier`) are substituted with their concrete values (like `10` or `20`) during compilation, resulting in fully independent Nix-reproducible pipelines.

---

## 27. Parallel Execution

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

## 28. Extended Inspection API

> [↩ Quick Reference: Pipeline DAG Structure](#3-pipeline-function-quick-reference)

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

### `pipeline_to_dot`

Exports the pipeline as a [Graphviz](https://graphviz.org/) DOT string for visualization. Works for both `Pipeline` and `MetaPipeline`:

```t
p = pipeline { a = 1; b = a + 1; c = b + 1 }

dot = pipeline_to_dot(p)
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

### `pipeline_to_mermaid`

Exports the pipeline as a [Mermaid](https://mermaid.js.org/) flowchart string:

```t
p = pipeline { a = 1; b = a + 1; c = b + 1 }

mermaid = pipeline_to_mermaid(p)
print(mermaid)
-- graph LR
--   a["a [T]"];
--   b["b [T]"];
--   c["c [T]"];
--   a --> b;
--   b --> c;
```

Render the Mermaid flowchart directly in markdown files or preview using the online Mermaid live editor.

#### Visualizing Mermaid Graphs in the Browser with `show_plot`

Rather than manually pasting the Mermaid string into an external editor, you can reuse `show_plot()` to visualize Mermaid graphs, pipelines, or meta-pipelines directly in your web browser:

```t
-- Visualize a pipeline directly:
show_plot(p)

-- Or visualize a raw Mermaid string:
show_plot("graph TD\n  Start --> Stop")
```

When you pass a pipeline, meta-pipeline, or a string starting with a Mermaid keyword (like `graph` or `flowchart`) to `show_plot()`, T dynamically generates a temporary HTML file containing the Mermaid JS engine, renders the graph, and opens it using your configured system viewer/browser.

---

## 29. Pipeline Validation

> [↩ Quick Reference: Pipeline DAG Structure](#3-pipeline-function-quick-reference)

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

## 30. Handling Ambiguous Dependencies

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

> See the [Pipeline Tutorial](pipeline_tutorial.md) for general pipeline best practices (descriptive names, focused nodes, pipes, inspect, incremental builds, validation).

7. **Compose with `chain` over `union`**: When two pipelines are intentionally connected, `chain` makes the dependency explicit; use `union` only when combining truly independent pipelines
8. **Use `filter_node` + `upstream_of` for partial builds**: Trim a large pipeline to just what you need before calling `build_pipeline`
9. **Resolve collisions with `rename_node` before set ops**: Both `union` and `chain` enforce unique names; rename conflicting nodes before merging

---

## 31. Cross-Node Artifact Retrieval

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

## 32. Nix-Native Orchestration & Cachix

To optimize large-scale pipelines and manage remote binary caching, T-Lang includes native Nix orchestration features in `build_pipeline` and `pipeline_run`. These features map directly to native `nix build` mechanics, allowing granular rebuild control, job parallelization, Cachix integration, and dry-runs.

### Orchestration Parameters

The functions `build_pipeline()` and `pipeline_run()` accept an optional `nix_options` dictionary containing the following keys:

| Key | Type | Description | Nix Command Mapping |
|---|---|---|---|
| `targets` | String/List/Vector | Specific node(s) or outputs to build (e.g., `targets: ["model_a"]`) | `-A <targets>` |
| `force` | Bool/String/List/Vector | Rebuild nodes even if they already exist in the Nix store. Pass `true` to force-rebuild all nodes, or a string/list of specific node names. | `--check` (rebuilds target) |
| `dry_run` | Bool | Preview build actions without executing them. Returns a structured `DataFrame` of planned actions. | `--dry-run` |
| `max_jobs` | Int | Limit parallel compilation/build jobs. | `--max-jobs N` |
| `cache` | String | A Cachix binary cache name (e.g., `"rstats-on-nix"`) to pull/push built artifacts. | `--option extra-substituters ...` & `--option extra-trusted-public-keys ...` |
| `builders` | String | Remote builder specification in SSH syntax. | `--builders ...` |
| `keep_env` | String/List/Vector | Environment variable names to pass into the Nix sandbox. | `--option keep-env ...` |
| `sandbox` | Bool/String | Sandboxing policy: `true`/`"strict"`, `"relaxed"`, or `false`/`"none"`. | `--option sandbox ...` |

### Using `dry_run` for Build Previews

If you set `dry_run: true` inside `nix_options`, T-Lang will invoke Nix in dry-run mode and return a structured `DataFrame` detailing the exact actions Nix plans to take (e.g., fetching from binary caches, building derivations):

```t
p = pipeline {
  a = 1
  b = a + 1
}

-- Inspect planned build actions without running them
actions = build_pipeline(p, nix_options = [dry_run: true])
print(actions)
```

The resulting `DataFrame` contains the columns:
- `node`: The name of the pipeline node.
- `action`: The action planned (e.g., `"build"`, `"substitute"`, or `"noop"`).
- `path`: The absolute store path of the Nix derivation or artifact.

### Advanced Nix Orchestration Example

Below is an example showing how to trigger a parallel, cache-backed build targeting a specific node:

```t
p = pipeline {
  a = 1
  b = a + 1
  c = b * 2
}

-- Rebuild only node 'c', with parallel execution, using a Cachix binary cache
build_pipeline(p,
               nix_options = [
                 targets: ["c"],
                 max_jobs: 4,
                 cache: "rstats-on-nix",
                 force: ["c"]
               ])
```

## 33. Granular Artifact Transfer & Archive Introspection

For teams working on large projects, T supports exporting Nix-materialized pipeline cache artifacts into portable archive files (`.nar` format). These archives can be transferred between machines, imported without rebuilding, or inspected without installing.

### Granular Artifact Export

To export cached artifacts, use `export_artifacts()`. In addition to entire pipelines, you can target specific sub-structures:

```t
p = pipeline {
  a = shn(command = "echo -n 'hello'", capture = "stdout")
  b = a |> \(x) x + " world"
}
build_pipeline(p)

-- 1. Export the entire pipeline's artifacts
export_artifacts(p, "full_cache.nar")

-- 2. Granular export: Export a single computed node
export_artifacts(p.a, "node_a.nar")

-- 3. Export a list or vector of nodes/pipelines
export_artifacts([p.a, p.b], "subset.nar")

-- 4. Export nested structures/dictionaries
export_artifacts([first: p.a, second: p.b], "dict_subset.nar")
```

### Variadic Artifact Import

To restore exported artifacts, use `import_artifacts()`. It is variadic and supports two calling conventions:

1. **Verification Import (2 arguments)**: Imports the archive and verifies that a specific pipeline, node, or value's paths exist in the local store.
2. **Immediate Store Import (1 argument)**: Unpacks and loads the archive directly into the local Nix store without needing a target object for verification. This is especially useful for setting up an environment prior to loading or parsing a pipeline script.

```t
-- Convention 1: Import and verify against a pipeline
import_artifacts(p, "full_cache.nar")

-- Convention 2: Load archive directly into the Nix store
import_artifacts("full_cache.nar")
```

### Archive Introspection

You can inspect the contents of an artifact archive file without unpacking it permanently or changing your local store. The `inspect_artifacts()` function imports the archive into a temporary, isolated Nix store, extracts metadata for each path, and returns a DataFrame.

```t
df = inspect_artifacts("full_cache.nar")

-- View the details of the archive
df
-- DataFrame with columns:
--   - node: The name of the node (if known)
--   - store_path: The Nix store path of the artifact
--   - hash: The SHA-256 hash of the store path
--   - size_bytes: The size of the unpacked artifact in bytes
--   - references: Comma-separated basenames of dependency store paths
```

### Cache-Aware Dry Runs

For convenience, you can perform a dry-run check directly using the `dry_run = true` parameter in `populate_pipeline()`. This reports which nodes are already in the Nix cache and which ones require rebuilding or downloading:

```t
p = pipeline {
  a = 1
  b = a + 1
}

-- Check cache hit/miss status directly
plan = populate_pipeline(p, dry_run = true)
print(plan)
-- Returns a DataFrame with columns: node, action, and path.
-- "action" will be one of:
--   - "cached": path is already built/cached locally
--   - "build": path must be rebuilt locally
--   - "fetch": path can be retrieved from remote binary substitutes
```

### Programmatic Garbage Collection

Over time, your local Nix store can accumulate unused derivations and cache files. T-Lang provides REPL functions to safely clean up OCaml/Nix artifacts directly:

1. **`pipeline_gc(p, dry_run = false)`**: Deletes the store paths of the given pipeline `p`. By default (`dry_run = true`), it queries what would be deleted and returns a DataFrame showing the `node`, `store_path`, and `deleted` status. Set `dry_run = false` to perform the actual deletion.
2. **`t_gc()`**: Performs a global Nix store garbage collection (`nix-store --gc`), removing all unused derivations and freeing up disk space.

```t
p = pipeline {
  a = 1
}

-- Preview what would be deleted
plan = pipeline_gc(p, dry_run = true)

-- Perform the deletion of the pipeline's nodes
pipeline_gc(p, dry_run = false)

-- Perform global garbage collection
t_gc()
```

---

## 34. CI/CD with GitHub Actions

T can generate a complete GitHub Actions workflow YAML for executing a pipeline via `pipeline_to_ga()`. The generated workflow:

1. Restores cached Nix artifacts from the `t-runs` branch (via `nix-store --import`)
2. Runs the pipeline via `nix develop --command t run <pipeline_script>`
3. Exports updated artifacts back to the `t-runs` branch

```t
-- Write the generated YAML directly to .github/workflows/<name>.yml (uses "src/pipeline.t" by default)
pipeline_to_ga()

-- Write directly to a custom path (e.g. .github/workflows/ci.yml)
pipeline_to_ga("src/run.t", file = ".github/workflows/ci.yml")

-- Get the generated YAML back as a string instead of writing to disk
yaml = pipeline_to_ga(file = "")
print(yaml)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `pipeline_script` | `String` | `"src/pipeline.t"` | Path to the pipeline T script. Can be passed as the first positional argument. |
| `name` | `String` | Auto-detected | Project name from `tproject.toml`. Controls the workflow display name, job ID, and NAR archive filename. |
| `file` | `String` | `".github/workflows/<name>.yml"` | Output file path. Defaults to `.github/workflows/<name>.yml`. Set to an empty string (`""`) to return the YAML workflow as a string without writing to disk. |

The auto-detected project name comes from the `name` field in your project's `tproject.toml`. If neither a `name` argument nor a `tproject.toml` is found, an error is raised prompting you to provide an explicit name.

---

## 35. Pattern-Based Branching

T lets you dynamically expand a single pipeline node into multiple branches using pattern functions. This is useful when you need to run the same computation over each element of a list, vector, or data frame.

Patterns are **automatically expanded** when you call `populate_pipeline()` or `build_pipeline()` — you do not need to call `expand_pipeline()` explicitly. The explicit function is available if you want to inspect the expanded structure before building.

### 11.1 `map_pattern` — One Branch Per Element

Use `map_pattern(dep)` to create one branch for each element of an upstream dependency:

```t
p = pipeline {
  x = [10, 20, 30]
  y = node(command = <{ x * 2 }>, pattern = map_pattern(x))
}

-- Auto-expansion happens inside build_pipeline:
build_pipeline(p)

-- Or inspect the expanded structure explicitly:
expanded = expand_pipeline(p)
pipeline_nodes(expanded)
-- ["x", "y_branch_1", "y_branch_2", "y_branch_3"]

expanded.y_branch_1  -- 20  (10 * 2)
expanded.y_branch_2  -- 40  (20 * 2)
expanded.y_branch_3  -- 60  (30 * 2)
```

Multiple dependencies can be mapped simultaneously — all must have the same length, and branch `i` receives element `i` from each:

```t
p = pipeline {
  xs = [1, 2, 3]
  ys = [10, 20, 30]
  z = node(command = <{ xs + ys }>, pattern = map_pattern(xs, ys))
}
-- build_pipeline(p) auto-expands before building
```

### 11.2 `cross_pattern` — Cartesian Product

Use `cross_pattern(sub1, sub2, ...)` for a Cartesian product of multiple `map_pattern` sub-patterns:

```t
p = pipeline {
  a = [1, 2]
  b = [10, 20]
  c = node(command = <{ a + b }>, pattern = cross_pattern(map_pattern(a), map_pattern(b)))
}
expanded = expand_pipeline(p)
pipeline_nodes(expanded)
-- ["a", "b", "c_branch_1", "c_branch_2", "c_branch_3", "c_branch_4"]
-- Branch order: (a=1,b=10), (a=1,b=20), (a=2,b=10), (a=2,b=20)
```

### 11.3 DataFrame Row Branching

When a dependency is a DataFrame, each row becomes one branch element:

```t
df = to_dataframe([[x: 10], [x: 20], [x: 30]])

p = pipeline {
  data = df
  result = node(command = <{ data }>, pattern = map_pattern(data))
}
expanded = expand_pipeline(p)
pipeline_nodes(expanded)
-- ["data", "result_branch_1", "result_branch_2", "result_branch_3"]
-- Each branch receives a 1-row DataFrame
```

### 11.4 Selector Patterns

For finer-grained control over which elements produce branches, use selector patterns.
All four take exactly one dependency and an integer parameter, and produce N branches
where N is determined by the parameter.

#### 11.4.1 `slice_pattern(dep, [i, j, ...])` — Branch on Specific Indices

Select specific indices (0-based) from the dependency. Each index in the list becomes one
branch. This is useful when you want to recompute only a subset of values, or when you
want to reorder branches.

```t
p = pipeline {
  x = [10, 20, 30, 40, 50]
  -- Only branches for indices 0, 2, 4:
  y = node(command = <{ x }>, pattern = slice_pattern(x, [0, 2, 4]))
}
-- expand_pipeline(p) produces:
--   y_branch_1 with x = 10  (index 0)
--   y_branch_2 with x = 30  (index 2)
--   y_branch_3 with x = 50  (index 4)
```

Indices must be within the dependency's bounds (0 ≤ i < length). Out-of-range indices
return an error at expansion time.

#### 11.4.2 `head_pattern(dep, n)` — Branch on First N Elements

Take the first `n` elements of the dependency. Each of the first N elements becomes
one branch. If `n` exceeds the dependency length, it is silently capped — you get at
most `length(dep)` branches.

```t
p = pipeline {
  x = [10, 20, 30, 40, 50]
  -- First two elements:
  y = node(command = <{ x }>, pattern = head_pattern(x, 2))
  -- First ten (capped at 5):
  z = node(command = <{ x }>, pattern = head_pattern(x, 10))
}
-- y produces 2 branches: y_branch_1 (x=10), y_branch_2 (x=20)
-- z produces 5 branches (one per element, since 10 > 5)
```

#### 11.4.3 `tail_pattern(dep, n)` — Branch on Last N Elements

Take the last `n` elements of the dependency. Branches are indexed from the end —
element at `length - n` becomes `branch_1`, and so on. Like `head_pattern`, n is
capped to the dependency length if it exceeds it.

```t
p = pipeline {
  x = [10, 20, 30, 40, 50]
  -- Last two elements:
  y = node(command = <{ x }>, pattern = tail_pattern(x, 2))
}
-- y produces 2 branches:
--   y_branch_1 with x = 40  (index 3)
--   y_branch_2 with x = 50  (index 4)
```

#### 11.4.4 `sample_pattern(dep, n)` — Randomly Select N Elements

Randomly select `n` elements from the dependency (without replacement — no duplicate
branches). Uses a Fisher-Yates partial shuffle seeded deterministically from the
node name (`Hashtbl.hash name`), so repeated expansions of the same pipeline always
produce the same random draw. Different node names produce different draws.
As with the other selectors, n is capped to the dependency length.

```t
p = pipeline {
  x = [10, 20, 30, 40, 50]
  -- Randomly pick 2 elements:
  y = node(command = <{ x }>, pattern = sample_pattern(x, 2))
}
-- y produces 2 branches with randomly chosen values from x.
-- The selection is deterministic: calling expand_pipeline(p) again on
-- the same pipeline always picks the same two indices.
```

#### Selector Patterns Summary

| Pattern | Branch count | Branches from |
|---|---|---|
| `slice_pattern(dep, [i, j, ...])` | `len(indices)` | Values at given indices |
| `head_pattern(dep, n)` | `min(n, length(dep))` | First n elements |
| `tail_pattern(dep, n)` | `min(n, length(dep))` | Last n elements |
| `sample_pattern(dep, n)` | `min(n, length(dep))` | Random n elements |

All four patterns are automatically expanded on `build_pipeline`, `populate_pipeline`,
and composition builtins (`chain`, `parallel`, `union`, etc.), just like `map_pattern`
and `cross_pattern`. They cannot be nested inside `cross_pattern()` — only
`map_pattern` is supported as a sub-pattern of `cross_pattern`.

### 11.5 Pattern Branching with Non-T Runtimes

Pattern branching works with non-T runtimes (`R`, `Python`, `Julia`, etc.), but requires explicit `serializer` and `deserializer` configuration so cross-runtime data interchange works correctly. Each branch runs under the same runtime as the original patterned node:

```t
p = pipeline {
  a = [1, 2, 3]
  b = node(
    command = <{ a }>,
    runtime = R,
    serializer = ^json,
    deserializer = ^json,
    pattern = map_pattern(a)
  )
}

build_pipeline(p)
-- Each branch (b_branch_1, b_branch_2, b_branch_3) runs in R
```

The serializer/deserializer symbols (`^json` in the example) must match a supported interchange format on both sides of the runtime boundary. If serializer and deserializer are omitted, expansion succeeds but the build will fail — the default serializer cannot produce runtime-specific artifacts for cross-runtime data interchange.

See §11.8 for a complete polyglot example using `cross_pattern` and `map_pattern` with R `ggplot2`.

### 11.6 Writing the Expanded Pipeline to a File

Pass `to_script` to write the expanded pipeline as a T source file for inspection or debugging:

```t
expand_pipeline(p, to_script = "expanded_pipeline.t")
```

The output file contains the full `pipeline { ... }` definition with all branches unrolled.

### 11.7 Build and Composition Auto-Expand

`populate_pipeline()`, `build_pipeline()`, `chain()`, `parallel()`, `union()`, `intersect()`, `difference()`, and `patch()` all automatically expand any unexpanded patterns in their pipeline inputs before proceeding. You only need to call `expand_pipeline()` explicitly when you want to inspect the branch structure before building.

### 11.8 Lazy Branch Access

Even before calling `expand_pipeline()`, you can inspect and interact with the branch structure of a patterned pipeline directly:

**List branch names** with `pipeline_nodes(p)`:

```t
p = pipeline {
  a = [10, 20, 30]
  b = map_pattern(a) ~> a * 2
}
pipeline_nodes(p)
-- Result: ["a", "b_branch_1", "b_branch_2", "b_branch_3"]
```

**Inspect branch structure** with `inspect_pipeline(p)`:

```t
inspect_pipeline(p)
-- DataFrame with one row per branch, including auto-generated branch names
```

**Access a branch by name** with dot notation — `p.b_branch_1` lazily synthesizes a `VComputedNode` without triggering expansion:

```t
b1 = p.b_branch_1
-- b1 is a computed node that will be resolved when built
```

**Helpful error on the parent node**: if you try `read_node(p.b)` on a patterned node before building, instead of a generic "not built yet" error you get a message listing the available branches:

```
Error(ValueError): Node `b` has a pattern and expands into b_branch_1, b_branch_2, b_branch_3.
  Use read_node(p.<branch_name>) to access individual branches directly.
```

**Reserved naming**: node names ending in `_branch_N` (e.g. `x_branch_1`) are reserved for auto-generated branch nodes. Using such a name at pipeline construction produces a `NameError`.

### 11.9 Complete Example: Polyglot Dynamic Branching Pipeline

This demo (from `t_demos/dynamic_branching_t`) combines `cross_pattern`, `map_pattern`, and cross-runtime (T ↔ R) serialization into a single end-to-end pipeline. It generates spirograph data points in T and plots them with R `ggplot2` — one plot per parameter combination.

#### Problem

You have a list of radii `[3, 5, 8]` and `[2, 4, 6]`. You want all 9 combinations of spirograph curves drawn as ggplot2 faceted plots. Writing 9 nodes by hand is tedious — use pattern branching instead.

#### Pipeline Definition

```t
p = pipeline {
  fixed_radii = [3, 5, 8]
  cycling_radii = [2, 4, 6]

  points = node(
    command = <{
      import "src/spirograph.t"
      spirograph_points(fixed_radii, cycling_radii)
    }>,
    pattern = cross_pattern(map_pattern(fixed_radii), map_pattern(cycling_radii)),
    runtime = T,
    serializer = ^json
  )

  single_plot = node(
    command = <{ plot_spirographs(points) }>,
    pattern = map_pattern(points),
    functions = ["src/spirograph.R"],
    runtime = R,
    deserializer = ^json
  )
}
```

#### How It Works

1. **`cross_pattern(map_pattern(fixed_radii), map_pattern(cycling_radii))`** — takes the Cartesian product of both lists (3 × 3 = 9). Each branch calls `spirograph_points(r_fixed, r_cycling)` from `src/spirograph.t` with one specific radius pair, returning a DataFrame of x, y coordinates.

2. **`serializer = ^json`** — the `points` node uses the `^json` symbol serializer to write each branch's DataFrame as a JSON array of records. Without this, the R node downstream cannot read the data.

3. **`map_pattern(points)`** — creates one branch per `points` output (9 branches total). Each branch calls `plot_spirographs()` from `src/spirograph.R`.

4. **`deserializer = ^json`** — Tells the pipeline runner to read the R node's JSON artifact back so it can be cached and inspected.

5. **`^json` symbol syntax** — required for serializer/deserializer values in cross-runtime pipelines (string literals like `"json"` are not accepted). This is the canonical way to declare interchange formats.

#### The Helper Code

**`src/spirograph.t`** — a parametric spirograph function called by each data branch:

```t
spirograph_points = \(fixed_radius, cycling_radius) {
  num_points = 10000
  max_t = 30 * pi
  t_values = float_seq(0, max_t, num_points)
  diff = fixed_radius - cycling_radius
  ratio = diff / cycling_radius
  xs = t_values |> map(\(t) diff * cos(t) + cos(t * ratio))
  ys = t_values |> map(\(t) diff * sin(t) - sin(t * ratio))
  to_dataframe([x: xs, y: ys,
    fixed_radius: fixed_radius,
    cycling_radius: cycling_radius])
}
```

**`src/spirograph.R`** — renders a faceted ggplot for one parameter combination:

```r
library(ggplot2)

plot_spirographs <- function(points) {
  label <- "fixed_radius = %s, cycling_radius = %s"
  points$parameters <- sprintf(label, points$fixed_radius, points$cycling_radius)
  ggplot(points) +
    geom_point(aes(x = x, y = y, color = parameters), size = 0.1) +
    facet_wrap(~parameters) +
    theme_gray(16) +
    guides(color = "none")
}
```

Note the `functions = ["src/spirograph.R"]` argument on the R node — this propagates the script into the Nix sandbox so it is available at build time.

#### Building

When you run `build_pipeline(p, verbose = 1)`, T automatically expands the patterns before building:

```
+ points_branch_1 building
+ points_branch_2 building
...
+ points_branch_9 building
+ single_plot_branch_3 building
+ single_plot_branch_5 building
...
+ single_plot_branch_1 building

✓ Pipeline build completed [20 built / 20 nodes]
```

20 nodes total: 2 root (`fixed_radii`, `cycling_radii`), 9 data branches, 9 plot branches.

#### Post-Build Verification

Since `build_pipeline` does not modify the original pipeline variable `p`, expanded branch nodes are only visible in the build log. Use `build_log_to_frame()` to inspect them:

```t
res = build_pipeline(p, verbose = 1)

node_frame = build_log_to_frame(res)
points_branches = filter(node_frame, \(r) starts_with(r.name, "points"))
plot_branches = filter(node_frame, \(r) starts_with(r.name, "single_plot"))

assert(nrow(points_branches) == 9, "Expected 9 points branches")
assert(nrow(plot_branches) == 9, "Expected 9 single_plot branches")
assert(length(res.failed_nodes) == 0, "All nodes should succeed")
```

This pattern — `build_log_to_frame(res)` + `filter` with a lambda — is the recommended way to verify branched pipeline builds when you need to inspect individual expanded nodes.

#### Key Takeaways

- **`cross_pattern(map_pattern(...), map_pattern(...))`** generates a Cartesian product of branches.
- **Chaining patterns** (`cross_pattern` → `map_pattern`) lets you build multi-phase branched pipelines.
- **`^json` serializer/deserializer** enables cross-runtime data interchange between T and R nodes.
- **Expanded nodes exist only in the build log**, not in the original pipeline variable. Use `build_log_to_frame()` for post-build queries.
- **Patterns work with non-T runtimes downstream** — a `map_pattern` node can depend on T data branches and run in R (or Python or Julia), as long as serialization is configured correctly.

---

## 36. Static Conditionals

T supports conditional node inclusion evaluated at pipeline construction time, preserving Nix's static DAG requirement. There are two functions: `node_when` and `node_fork`.

### `node_when(condition, value)`

Returns `value` if `condition` is truthy, otherwise returns a null marker that causes the pipeline to exclude the node entirely. The condition is evaluated before the build.

```t
p = pipeline {
  dev_data = read_csv("data/dev.csv")

  model = node_when(env("CI") == "1", pyn(script = "train.py"))

  deployed = node_when(env("BRANCH") == "main", pyn(script = "deploy.py"))
}

build_pipeline(p)
```

If `CI` is not `"1"`, the `model` node is excluded and no attempt is made to resolve its dependencies. If `BRANCH` is not `"main"`, the `deployed` node is similarly excluded.

### `node_fork(...condition_value_pairs, .default = ...)`

A multi-way branch: takes condition-value pairs and returns the value for the first truthy condition. If no condition matches and no `.default` is provided, the node is excluded.

```t
p = pipeline {
  data = read_csv("data.csv")

  model = node_fork(
    env("MODEL") == "linear", lm(mpg ~ wt, data),
    env("MODEL") == "forest", pyn(script = "rf.py"),
    env("MODEL") == "neural", pyn(script = "nn.py"),
    .default = lm(mpg ~ wt, data)
  )
}
```

Here, setting `MODEL=forest` in the environment selects the random forest node; any other value falls back to the `.default` linear model.

### Important Notes

- Both `node_when` and `node_fork` are only meaningful as the direct value of a node binding inside a `pipeline { }` block. Using the result outside that context (arithmetic, `is_na()`, etc.) is unsupported.
- Conditions must be evaluable at pipeline construction time — typically using `env()` to read environment variables.
- The null marker from an unmatched condition is not a regular value; it cannot be inspected, stored, or tested with `is_na()`. It exists only to signal node exclusion to the pipeline machinery.

---

## Next Steps

Now that you've mastered pipelines, learn how to manage reproducible projects and develop T packages:

1. **[Project Development](project_development.md)** — Master T's project structure and dependency management.
2. **[Package Development](package_development.md)** — Create reusable T libraries.
3. **[Reproducibility Guide](reproducibility.md)** — Deep dive into T's commitment to reproducible research.
4. **[API Reference](api-reference.md)** — Complete function reference by package.
