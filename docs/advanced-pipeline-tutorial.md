# Advanced Pipeline Tutorial

> Dynamic branching, node manipulation, pipeline composition, and beyond

This guide covers advanced pipeline features building on the fundamentals from the [Pipeline Tutorial](pipeline_tutorial.md). You should be familiar with basic pipeline concepts (nodes, dependencies, building, and inspecting) before diving in here.

Once you are comfortable manipulating pipelines as data, continue to [Pipeline Materialization & Nix Orchestration](pipeline-materialization.md) for building pipelines into reproducible Nix artifacts, orchestrating builds, transferring archives, and customizing per-node build environments.

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

> [↩ Quick Reference: Pipeline DAG Structure](pipeline_tutorial.md#pipeline-function-quick-reference)

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
  b = node(command = <{ 2 }>, runtime = R, serializer = ^pmml)
  c = b + 1
}

p |> select_node($name, $runtime, $depth)
-- DataFrame: name="a", runtime="T", depth=0
--            name="b", runtime="R", depth=0
--            name="c", runtime="T", depth=1
```

Available fields: `$name`, `$runtime`, `$serializer`, `$deserializer`, `$noop`, `$deps`, `$depth`, `$command_type`.

### `pipeline_config_to_frame`

`pipeline_config_to_frame` extends `pipeline_to_frame` by adding resolved configuration values and provenance columns: one row per node with identity fields, resolved scalars, per-field provenance source markers, and global/node count splits for every list option. See the [API reference](api-reference.md#pipeline_config_to_framep) for the full column list.

```t
p = pipeline {
  a = rn(command = <{ 1 }>, functions = ["a.R"])
  b = pyn(command = <{ 2 }>)
}
q = set_pipeline_global_options(p, functions = [rn: "global.R"], serializer = ^json)

pipeline_config_to_frame(q)
-- DataFrame(2 rows)
```

Because the provenance columns are plain DataFrame columns, you can query them with the standard verbs:

```t
pipeline_config_to_frame(q)
  |> filter($prov_serializer == "global")
  |> select($name, $serializer)
-- The row for every node whose serializer came from global options
```

> [!NOTE]
> `n_deps` counts **auto-inferred** dependencies (`p_deps`), while its provenance split (`n_deps_global` / `n_deps_node`) only tracks explicitly-declared or globally-injected deps — so `n_deps` can exceed the sum for nodes with auto-inferred edges. The other list-count groups reconcile because they come from the same underlying lists as their provenance columns.

See [§4.4 of the Pipeline Tutorial](pipeline_tutorial.md#reading-back-a-nodes-resolved-configuration) for the provenance model behind these columns.

---

## 20. Environment Variables

Pipeline nodes can pass environment variables into the Nix build sandbox via the `env_vars` named argument on `node()`, `pyn()`, `rn()`, `jln()`, `qn()`, and `shn()`. This allows nodes to configure their build-time execution environment without embedding those values directly into the command body.

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
  model  = rn(command = <{ lm(y ~ x, data = load) }>, serializer = ^pmml)
  score_result  = node(command = predict(model, load), deserializer = ^pmml)
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

-- Swap a node's function files, arguments, and shell interpreter
p |> mutate_node(
  $functions = ["utils.R"],
  $args = [FLAGS: "-O2"],
  $shell = "bash",
  $shell_args = ["-lc"]
)
```

#### Mutable Fields

`mutate_node` can update a node's `runtime`, `serializer`/`deserializer`, `noop` flag, `deps`, `functions`, `include`, `env_vars`, `args`, `shell`, `shell_args`, and `flake` configuration. See the [API reference](api-reference.md#mutate_nodep-...-rename_nodep-...) for the complete list with types.

Unlike `set_pipeline_global_options` (which **combines/prepends** mergeable lists), `mutate_node` **replaces** the field's value entirely — whatever you pass becomes the new value.

#### Clearing Fields with `NA`

Pass `NA` to clear an optional or list/dict field:

```t
-- Remove the per-node shell and flake overrides
p |> mutate_node($shell = NA, $flake = NA)

-- Empty out the function files and env vars
p |> mutate_node($functions = NA, $env_vars = NA)
```

One exception: `deps` **cannot** be cleared with `NA`, because dependency edges cannot be safely re-derived outside the original evaluation environment. Mutating `deps` to a concrete list is fine; clearing it to `NA` returns an error telling you to re-run the pipeline to rebuild the dependency graph.

#### Provenance

Every field you mutate is marked as **`node`-sourced** in provenance tracking. After `p |> mutate_node($functions = ["utils.R"])`, `pipeline_node_options(p, "a").provenance.functions` shows `{ global: [], node: ["utils.R"] }` — even if the pipeline previously had a global `functions` option for that node, the mutation overrides it and provenance records the fact.

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
  row_count = nrow(filtered)
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
  model = rn(command = <{ lm(y ~ x, data = load) }>, serializer = ^pmml)
}

p_overrides = pipeline {
  model = rn(command = <{ lm(y ~ x + z, data = load) }>, serializer = ^pmml)
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
  model = rn(command = <{ lm(y ~ x, data = data) }>, serializer = ^pmml)
  score_result = node(command = predict(model, data), deserializer = ^pmml)
}

-- Replace the model node with a new implementation; edges to/from model are preserved
new_model = rn(command = <{ glm(y ~ x, data = data, family = binomial) }>, serializer = ^pmml)
p2 = p |> swap("model", new_model)

pipeline_deps(p2)
-- `model` still depends on `data`, and `score_result` still depends on `model`
```

### `rewire`

Reroutes a node's declared dependencies. The `replace` argument maps old dependency names to new ones. Only the named node's dependency list is updated.

```t
p = pipeline {
  data    = read_csv("data.csv")
  data_v2 = read_csv("data_v2.csv")
  model   = rn(command = <{ lm(y ~ x, data) }>, serializer = ^pmml)
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
  model   = rn(command = <{ lm(y ~ x, clean) }>, serializer = ^pmml)
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
  summary_result = etl.clean |> mean
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

When a meta-pipeline is populated, queried, or inspected, T-Lang automatically flattens it internally. Node names are automatically namespaced (e.g. `etl.raw`, `etl.clean`, `stats.summary_result`) to prevent namespace collisions, and all internal variable references are rewritten accordingly.

```t
pipeline_nodes(meta)
-- ["etl.raw", "etl.clean", "stats.summary_result"]

pipeline_deps(meta)
-- {`etl.raw`: [], `etl.clean`: ["etl.raw"], `stats.summary_result`: ["etl.clean"]}

-- You can build the entire meta-pipeline directly:
populate_pipeline(meta, build = true)

-- You can read individual nodes using nested dot notation:
res = read_node(meta.stats.summary_result)
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
  deserializer = ^ipc)
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
  r_fit = rn(command = <{ lm(y ~ x, data) }>, serializer = ^pmml)
}

p_py_model = pipeline {
  py_fit = pyn(
    command = <{
      from sklearn.linear_model import LinearRegression
      LinearRegression().fit(X, y)
    }>,
    serializer = ^pmml
  )
}

-- Both models will run independently
p_both = parallel(p_r_model, p_py_model)
pipeline_nodes(p_both)  -- ["r_fit", "py_fit"]
```

---

## 28. Extended Inspection API

> [↩ Quick Reference: Pipeline DAG Structure](pipeline_tutorial.md#pipeline-function-quick-reference)

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
  b = node(command = <{ 2 }>, runtime = R, serializer = ^pmml)
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

> [↩ Quick Reference: Pipeline DAG Structure](pipeline_tutorial.md#pipeline-function-quick-reference)

By design, T uses **lazy validation**: structural errors surface at `build_pipeline` or `pipeline_run` time, not at operation time. This allows you to compose and transform pipelines freely.

When you want to validate eagerly, T provides opt-in validation utilities. All of them are backed by a single **shared validator** that also guards `populate_pipeline`/`build_pipeline`, the eval-time cross-runtime check, and `t check` tier 1 — so the same structural guarantees are enforced everywhere, whether you validate eagerly or let the build catch problems.

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

1. No dependency cycles — the graph must be a DAG (malformed graphs).
2. All referenced dependencies exist as nodes in the pipeline (missing nodes).
3. Every node uses a known runtime (`T`, `R`, `Python`, `Julia`, `Quarto`, `sh`, `fetchurl`).
4. Cross-runtime dependencies declare an explicit deserializer (R/Python/Julia consumers of a dependency in a different runtime must set one).
5. Multiple dependencies on a single non-dictionary deserializer strategy — a node with several dependencies should use a per-dependency dictionary rather than one format for all.
6. Serializer/deserializer format coherence across dependency edges — a consumer's expected format matches what its producer emits.
7. All referenced `functions`, `include`, and `script` files exist on the file system.
8. The `^bin` serializer is only used by `fetchurl` nodes.

Errors are classified as `StructuralError`, `FileError`, or `TypeError`, which drives how each surface (the REPL error, the `pipeline_validate` list, and the `t check` JSON diagnostics) renders them. Within each check, results are reported deterministically — file order first, then pipeline declaration order.

### `t check` Tier 1

The same checks run when you execute `t check <file.t>` — T's instant structural checker that needs no Nix or runtime dependencies. `t check` parses the pipeline script, builds the DAG, and reports any of the above problems as structured diagnostics with a non-zero exit code, matching the build path's guarantees. See [Instant Feedback: `t check`](llm-collaboration.md#instant-feedback-t-check) for the full command surface.

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
  summary_result = shn(
    command = <{ cat data.csv | wc -l }>, 
    deps = [raw_file],
    serializer = ^text
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
10. **Audit provenance before refactoring global options**: Before moving settings between `set_pipeline_global_options` and per-node declarations, use `pipeline_config_to_frame` (filter on `$prov_serializer == "global"`) or the `provenance` key of `pipeline_node_options` to see exactly which nodes rely on each global option

---

## Next Steps

Now that you've mastered pipeline manipulation and composition, explore the build side of pipelines:

1. **[Pipeline Materialization & Nix Orchestration](pipeline-materialization.md)** — Building pipelines into reproducible Nix artifacts, orchestrating builds, transferring archives, CI/CD, branching, and custom flakes.
2. **[Project Development](project_development.md)** — Master T's project structure and dependency management.
3. **[Package Development](package_development.md)** — Create reusable T libraries.
4. **[Reproducibility Guide](reproducibility.md)** — Deep dive into T's commitment to reproducible research.
5. **[API Reference](api-reference.md)** — Complete function reference by package.

