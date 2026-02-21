# Pipeline Tutorial

> A step-by-step guide to T's pipeline execution model

Pipelines are T's core execution model. They let you define named computation steps (nodes) that are automatically ordered by their dependencies, executed deterministically, and cached for re-use.

---

## 1. Your First Pipeline

A pipeline is a block of named expressions enclosed in `pipeline { ... }`:

```t
p = pipeline {
  x = 10
  y = 20
  total = x + y
}
```

This creates a pipeline with three nodes: `x`, `y`, and `total`. Each node is computed once, and the results are cached. Access any node's value with dot notation:

```t
p.x      -- 10
p.y      -- 20
p.total  -- 30
```

The pipeline itself displays as:

```
Pipeline(3 nodes: [x, y, total])
```

---

## 2. Automatic Dependency Resolution

Nodes can be declared in **any order**. T automatically resolves dependencies:

```t
p = pipeline {
  result = x + y   -- depends on x and y
  x = 3            -- defined after result
  y = 7            -- defined after result
}
p.result  -- 10
```

T builds a dependency graph and executes nodes in topological order, so `x` and `y` are computed before `result` regardless of declaration order.

---

## 3. Chained Dependencies

Nodes can depend on other computed nodes, forming chains:

```t
p = pipeline {
  a = 1
  b = a + 1     -- depends on a
  c = b + 1     -- depends on b
  d = c + 1     -- depends on c
}
p.d  -- 4
```

---

## 4. Pipelines with Functions

Nodes can use any T function, including standard library functions:

```t
p = pipeline {
  data = [1, 2, 3, 4, 5]
  total = sum(data)
  count = length(data)
}
p.total  -- 15
p.count  -- 5
```

---

## 5. Pipelines with Pipe Operators

The pipe operator `|>` works naturally inside pipelines:

```t
double = \(x) x * 2

p = pipeline {
  a = 5
  b = a |> double
}
p.b  -- 10
```

### Error Recovery with Maybe-Pipe

The maybe-pipe `?|>` forwards all values — including errors — to the next function.
This is useful for building recovery logic into pipelines:

```t
recovery = \(x) if (is_error(x)) 0 else x
double = \(x) x * 2

p = pipeline {
  raw = 1 / 0                    -- Error: division by zero
  safe = raw ?|> recovery        -- forwards error to recovery → 0
  result = safe |> double        -- 0 |> double → 0
}
p.safe    -- 0
p.result  -- 0
```

Without `?|>`, the error from `raw` would short-circuit at `|>` and never reach `recovery`. The maybe-pipe lets you intercept errors and provide fallback values.

---

## 6. Data Pipelines

Pipelines are most powerful for data analysis workflows. Here's a complete example loading, transforming, and summarizing data:

```t
p = pipeline {
  data = read_csv("employees.csv")
  rows = data |> nrow
  cols = data |> ncol
  names = data |> colnames
}

p.rows   -- number of rows
p.cols   -- number of columns
p.names  -- list of column names
```

### Full Data Analysis Pipeline

```t
p = pipeline {
  raw = read_csv("sales.csv")
  filtered = filter(raw, $amount > 100)
  by_region = filtered |> group_by($region)
  summary = by_region |> summarize($total = sum($amount))
}

p.summary  -- DataFrame with regional totals
```

---

## 7. Pipeline Introspection

T provides functions to inspect pipeline structure:

### List all nodes

```t
p = pipeline { x = 10; y = 20; total = x + y }
pipeline_nodes(p)  -- ["x", "y", "total"]
```

### View dependency graph

```t
pipeline_deps(p)
-- {`x`: [], `y`: [], `total`: ["x", "y"]}
```

### Access a specific node by name

```t
pipeline_node(p, "total")  -- 30
```

---

## 8. Re-running Pipelines

Use `pipeline_run()` to re-execute a pipeline:

```t
p2 = pipeline_run(p)
p2.total  -- 30 (re-computed)
```

Re-running produces the same results — T pipelines are deterministic.

---

## 9. Deterministic Execution

Two pipelines with the same definitions always produce the same results:

```t
p1 = pipeline { a = 5; b = a * 2; c = b + 1 }
p2 = pipeline { a = 5; b = a * 2; c = b + 1 }
p1.c == p2.c  -- true
```

---

## 10. Error Handling

### Cycle Detection

T detects circular dependencies and reports them:

```t
pipeline {
  a = b
  b = a
}
-- Error(ValueError: "Pipeline has a dependency cycle involving node 'a'")
```

### Error Propagation

If a node fails, the error is captured and reported:

```t
pipeline {
  a = 1 / 0
  b = a + 1
}
-- Error(ValueError: "Pipeline node 'a' failed: ...")
```

### Missing Nodes

Accessing a non-existent node returns a structured error:

```t
p = pipeline { x = 10 }
p.nonexistent
-- Error(KeyError: "node 'nonexistent' not found in Pipeline")
```

---

## 11. Materializing Pipelines

Defining a pipeline with `pipeline { ... }` evaluates nodes in-memory. To **materialize** them as reproducible Nix artifacts, use `populate_pipeline()` with the `build = true` argument:

```t
p = pipeline {
  data = read_csv("sales.csv")
  total = sum(data.$amount)
}

populate_pipeline(p, build = true)
```

`populate_pipeline(p, build = true)` is the primary command for materializing a pipeline. It does the following:

1. **Populates** the `_pipeline/` directory with `pipeline.nix` and `dag.json`.
2. **Generates** a Nix expression with one derivation per node.
3. **Triggers** a Nix build to materialize each node as a serialized artifact.
4. **Records** the build in a timestamped log file (`_pipeline/build_log_YYYYMMdd_HHmmss_hash.json`).

> [!NOTE]
> `build_pipeline(p)` is available as a shorthand for `populate_pipeline(p, build = true)`.

### Reading built artifacts

After building, use `read_node()` or `load_node()` to retrieve materialized values:

```t
read_node("total")   -- reads the serialized artifact for "total"
load_node("total")   -- same as read_node, loads the artifact
```

These functions look up the node in the **latest build log** and deserialize the artifact.

---

## 12. Orchestrating with populate_pipeline()

For more control over the build process, T provides `populate_pipeline()`. This function prepares the pipeline infrastructure without necessarily triggering the Nix build immediately.

```t
populate_pipeline(p)                -- Prepares _pipeline/ only
populate_pipeline(p, build = true)  -- Same as build_pipeline(p)
```

### The `_pipeline/` directory

T maintains a persistent state directory for your pipeline. When you populate or build, T creates:

- **`_pipeline/pipeline.nix`**: The generated Nix expression for your pipeline nodes.
- **`_pipeline/dag.json`**: A machine-readable dependency graph of your pipeline.
- **`_pipeline/build_log_*.json`**: History of previous successful builds.

---

## 13. Build Logs and Time Travel

T keeps a history of your builds in `_pipeline/`. This enables **Time Travel** — the ability to read artifacts from specific past versions of your pipeline.

### Inspecting logs

Use `inspect_pipeline()` to see available build logs:

```t
logs = inspect_pipeline()
-- ["build_log_20260221_143022_abc123.json", ...]
```

### Reading from a specific build

Pass the `which_log` argument to `read_node()` to specify which build to read from. You can pass a regex pattern or a specific filename:

```t
-- Read the latest version (default)
val = read_node("result")

-- Read from a specific historical build
val_old = read_node("result", which_log = "20260221_143022")
```

This ensures that even as you update your code and data, you can always recover and compare results from previous runs.

---

## 14. Execution Modes

T enforces a clear separation between interactive and non-interactive execution:

### Non-interactive (`t run`)

Scripts executed with `t run` **must** call `populate_pipeline()` (or `build_pipeline()`). This ensures that non-interactive execution always produces reproducible Nix artifacts.

```bash
# ✅ This works — script defines and populates a pipeline
$ t run my_pipeline.t

# ❌ This is rejected — script doesn't call populate_pipeline()
$ t run my_script.t
# Error: non-interactive execution requires a pipeline.
# Scripts run with `t run` must call `populate_pipeline(p, build=true)`.
# Use the REPL for interactive exploration, or pass --unsafe to override.
```

A valid pipeline script looks like:

```t
-- my_pipeline.t
p = pipeline {
  data = read_csv("input.csv")
  result = data |> filter($value > 0) |> summarize(total = sum($value))
}

populate_pipeline(p, build = true)
```

### Interactive (REPL)

The REPL is **unrestricted** — you can run any T code line by line, whether or not it involves pipelines:

```bash
$ t repl
T> x = 1 + 2
T> print(x)
3
T> p = pipeline { a = 10 }
T> p.a
10
```

---

## 15. Using Imports in Pipelines

When a pipeline is built with `build_pipeline()`, each node runs inside a **Nix sandbox** — an isolated build environment. Import statements from your script are **automatically propagated** into each sandbox, so imported packages and functions are available to all nodes.

```t
-- my_analysis.t
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

## 16. Using explain() with Pipelines

The `explain()` function provides structured metadata about pipelines:

```t
p = pipeline {
  x = 10
  y = x + 5
  z = y * 2
}

e = explain(p)
e.kind        -- "pipeline"
e.node_count  -- 3
```

---

## Best Practices

1. **Name nodes descriptively**: Use names like `raw_data`, `filtered_sales`, `summary_stats`
2. **Keep nodes focused**: Each node should do one thing
3. **Use pipes within nodes**: Combine pipeline structure with pipe operator for readability
4. **Inspect before consuming**: Use `pipeline_nodes()` and `pipeline_deps()` to understand pipeline structure
5. **Build incrementally**: Start with data loading, add transformations one node at a time

---

## Complete Example

```t
-- A full data analysis pipeline
p = pipeline {
  -- Load data
  raw = read_csv("employees.csv")
  
  -- Filter to active engineers
  engineers = raw
    |> filter($dept == "eng")
    |> filter($active == true)
  
  -- Compute statistics
  avg_salary = engineers.salary |> mean
  salary_sd = engineers.salary |> sd
  team_size = engineers |> nrow
  
  -- Sort by performance
  ranked = engineers |> arrange("score", "desc")
}

-- Access results
p.team_size     -- number of active engineers
p.avg_salary    -- mean salary
p.ranked        -- DataFrame sorted by score
```
