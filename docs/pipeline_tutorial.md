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

### 1.1 The Interactive Development Loop

A productive way to build pipelines is incrementally in the REPL — start small, build, inspect, extend:

```t
p = pipeline { raw_data = [1, 2, 3, 4, 5] }
build_pipeline(p)
p.raw_data     -- [1, 2, 3, 4, 5]
read_node(p.raw_data)  -- verify serialized artifact
show_plot(p)   -- visualize the DAG
```

Then add a node and rebuild:

```t
p = pipeline {
  raw_data = [1, 2, 3, 4, 5]
  total = sum(raw_data)
}
build_pipeline(p)
p.total        -- 15
show_plot(p)   -- updated DAG with raw_data → total
```

Because `raw_data` was already built and cached, Nix skips rebuilding it and only computes the new `total` node. Run `build_pipeline(p, dry_run = true)` to preview cache hits vs rebuilds.

This **Build → Verify → Plot → Extend** loop lets you grow complex pipelines reliably, one node at a time.

---

## 2. Execution Modes

T enforces a clear separation between interactive and non-interactive execution.

### Interactive (REPL)

The REPL is unrestricted — you can run any T code line by line, whether or not it involves pipelines:

```bash
$ t repl
T> x = 1 + 2
T> p = pipeline { a = 10 }
T> p.a
10
```

### Non-interactive (`t run`)

Scripts executed with `t run` **must** call `populate_pipeline()` (or `build_pipeline()`). This ensures that non-interactive execution always produces reproducible Nix artifacts.

```bash
$ t run my_pipeline.t
```

```t
-- my_pipeline.t
p = pipeline {
  data = read_csv("input.csv")
  result = data |> filter($value > 0) |> summarize(total = sum($value))
}
populate_pipeline(p, build = true)
```

By default, `t run` operates in **resilient mode**, continuing past errors. Use `--failfast` to stop at the first error.

---

## 3. Pipeline Function Quick Reference

A consolidated index of all pipeline reading, inspecting, and build-log functions. Use this as a cheatsheet to find the right tool for the job.

### Reading Node Artifacts

| Function | Parameters | Returns | What it does |
|---|---|---|---|
| `read_node(node)` | `ComputedNode` | deserialized value + diagnostics | Read in-scope pipeline node artifact |
| `read_past_node(p.name, which_log)` | NSE-captured node, `String` (required) | deserialized value + diagnostics | Read from historical build log without pipeline in scope |
| `read_pipeline(p)` | `Pipeline` | `Dict` | Per-node values + diagnostics + aggregated summary |
| `pipeline_node(p, name)` | `Pipeline`, `String` | `Any` | Value of a specific node by name |

### Build Logs & History

| Function | Parameters | Returns | What it does |
|---|---|---|---|
| `build_log(p, which_log?)` | `Pipeline`, optional `String` | `BuildLog` | Structured build log for latest (or specified) build |
| `build_log_to_frame(log)` | `BuildLog` | `DataFrame` | Build log as DataFrame (name, status, duration, path) |
| `build_log_history(p, n?, pattern?)` | `Pipeline`, optional `Int`, `String` | `DataFrame` | History of all builds matching pipeline's node signature |
| `list_logs()` | — | `DataFrame` | All log files in `_pipeline/` (filename, mtime, size, pipeline) |
| `inspect_log(p?, which_log?)` | optional `Pipeline`, optional `String` | `DataFrame` | Derivation-level build status (derivation, build_success, path) |
| `read_log(node_name)` | `String` | `String` | Raw Nix build log text for a specific node |

### Node Inspection & Diagnostics

| Function | Parameters | Returns | What it does |
|---|---|---|---|
| `inspect_node(node)` | `ComputedNode` | `Dict` | Static metadata (runtime, path, class, deps) + structured warnings |
| `warning_msg(node)` | `ComputedNode` | `String` | Formatted warning message (own + upstream with source prefix) |
| `collect_exceptions(p)` | `Pipeline` | `DataFrame` | Structured error/warning DataFrame from built pipeline |
| `suppress_warnings(val)` | `Any` | original value | Suppress console warnings for a node; still accessible via `warning_msg()` |
| `debug_node(node)` | `ComputedNode` | `NA` | Interactive REPL subshell pre-configured with node environment |
| `rebuild_node(node)` | `ComputedNode` | `ComputedNode` | Rebuild a single node and return updated artifact path |

### Pipeline DAG Structure

| Function | Parameters | Returns | What it does |
|---|---|---|---|
| `pipeline_to_frame(p)` | `Pipeline` | `DataFrame` | Full node metadata (runtime, serializer, deps, depth, command_type) |
| `pipeline_config_to_frame(p)` | `Pipeline` | `DataFrame` | Node config + provenance: resolved values, per-field source (`global`/`node`), and global/node counts for every list option |
| `pipeline_nodes(p)` | `Pipeline` | `List[String]` | All node names |
| `pipeline_deps(p)` | `Pipeline` | `Dict` | Node name → list of dependency names |
| `pipeline_edges(p)` | `Pipeline` | `List[[from, to]]` | Edge list as dependency pairs |
| `pipeline_roots(p)` | `Pipeline` | `List[String]` | Nodes with no dependencies |
| `pipeline_leaves(p)` | `Pipeline` | `List[String]` | Nodes that nothing depends on |
| `pipeline_depth(p)` | `Pipeline` | `Int` | Maximum topological depth |
| `pipeline_cycles(p)` | `Pipeline` | `List[String]` | Nodes involved in cycles (empty = valid) |
| `pipeline_validate(p)` | `Pipeline` | `List[String]` | All structural validation errors (empty = valid); checks missing files, unknown runtimes, missing deps, cycles, cross-runtime deserializer gaps, serializer coherence, multi-dep deserializer strategies, and `^bin`-only-for-fetchurl. Same checks power `populate_pipeline`, `build_pipeline`, and `t check` tier 1 |
| `pipeline_assert(p)` | `Pipeline` | `Pipeline` | Throws first error, or returns pipeline unchanged |
| `pipeline_print(p)` | `Pipeline` | `NA` | Pretty-print node table to stdout |
| `pipeline_to_dot(p)` | `Pipeline` \| `MetaPipeline` | `String` | Graphviz DOT representation |
| `pipeline_to_mermaid(p)` | `Pipeline` \| `MetaPipeline` | `String` | Mermaid flowchart diagram |
| `trace_nodes(p, name?)` | `Pipeline`, optional `String` | `NA` | Visual dependency tree printer |
| `pipeline_cache_status(p)` | `Pipeline` | `DataFrame` | Nix store cache hits per node (cached, store_path) |
| `pipeline_to_drv(p)` | `Pipeline` | `Dict` | Node → derivation (.drv) path mapping |
| `pipeline_to_store(p)` | `Pipeline` | `Dict` | Node → Nix store output path mapping |

### Node-Level Filtering & Diffs

| Function | Parameters | Returns | What it does |
|---|---|---|---|
| `select_node(p, ...)` | `Pipeline`, `Symbol`... | `DataFrame` | Column projection from `pipeline_to_frame` |
| `which_nodes(p, predicate)` | `Pipeline`, `Function` (NSE) | `List` | Node records from `read_pipeline(p).nodes` matching predicate |
| `errored_nodes(p)` | `Pipeline` | `List` | Convenience wrapper: nodes with non-NA `diagnostics.error` |
| `node_diff(a, b, log_a?, log_b?)` | `ComputedNode` ×2, optional `String`/`Int` | `VDict` | Compare node artifacts across builds |
| `pipeline_diff(a, b)` | `Pipeline` ×2 | `Dict` | Structural diff between two pipeline DAGs |

### Export / Import / GC

| Function | Parameters | Returns | What it does |
|---|---|---|---|
| `pipeline_copy(node?, target_dir?)` | optional `String`, `String` | `String` | Copy artifacts from Nix store to local directory |
| `export_artifacts(p, archive)` | `Pipeline`, `String` | `String` | Export cached artifacts to portable archive |
| `import_artifacts(target_or_archive, archive?)` | `Pipeline` or `String`, optional `String` | `String` | Import previously exported archive |
| `inspect_artifacts(archive)` | `String` | `DataFrame` | Preview archive contents without importing |
| `pipeline_gc(p, dry_run?)` | `Pipeline`, optional `Bool` | `DataFrame` | GC pipeline store paths (dry_run=true previews) |
| `t_gc()` | — | `String` | Global Nix garbage collection |

### Global Options

| Function | Parameters | Returns | What it does |
|---|---|---|---|
| `set_pipeline_global_options(p, functions?, include?, env_vars?, serializer?, deserializer?, noop?, args?, shell?, shell_args?, flake?, dependencies?, runtimes?, nodes?)` | `Pipeline` plus optional `Dict`/`String`/`List`/`Bool` settings | `Pipeline` | Returns a new pipeline with global defaults merged into target nodes (all nodes by default). Original unchanged. Merge semantics: `functions`, `include`, `env_vars`, `args`, `shell_args`, `dependencies` prepend global values before per-node values (per-node dict keys win); `serializer`, `deserializer`, `shell`, `flake` override per-node values entirely; `noop = true` forces every node to no-op (`false` has no effect). `runtimes`/`nodes` restrict the merge to a subset (union when both given). |
| `pipeline_node_options(p, node)` | `Pipeline`, `String` | `Dict` | Read-back: returns the fully resolved configuration of a single node after any global-options merges (runtime, serializer, functions, env_vars, shell, flake, deps, depth, ...). Unknown node is a `TypeError`. |

---

## 4. Explicit Node Configuration

In addition to bare assignments, you can explicitly configure nodes using the `node()` function. This lets you define the execution environment (like the `runtime`) and custom serialization methods for when a pipeline is materialized by Nix:

```t
p = pipeline {
  data = node(command = read_csv("data.csv"), runtime = T)
  
  -- Running a Python node that trains a model using the pyn wrapper
  model = pyn(
    command = <{
        from sklearn.linear_model import LinearRegression
        fit = LinearRegression().fit(X, y)
        fit
    }>,
    serializer = "pmml"
  )
}
```

Bare syntax (like `x = 10`) is automatically desugared to `x = node(command = 10, runtime = T, serializer = default, deserializer = default)`. You can also use `pyn()`, `rn()`, and `shn()` as shortcuts for Python, R, and shell runtimes. T enforces cross-runtime safety: if a node with a non-`T` runtime depends on a `T` node, or vice versa, you should specify an explicit `serializer`/`deserializer`.

When an R node returns a `ggplot2` object, a Python node returns a `matplotlib` / `plotnine` plot object, or a Julia node returns a `TidierPlots.jl`, `Plots.jl`, or `Makie.jl` figure object, T preserves lightweight plot metadata for REPL inspection. Reading or printing those artifacts shows a structured summary with the plot class (`ggplot`, `matplotlib`, `plotnine`, `tidierplots`, `plotsjl`, or `makie`), runtime backend (`R`, `Python`, or `Julia`), title, labels, mappings when available, and layer information instead of a raw runtime-specific object dump.

### Using the `script` Argument

Instead of inlining code with `command`, you can point a node to an external source file using the `script` argument. This works with `node()`, `pyn()`, `rn()`, and `shn()`. The `script` and `command` arguments are mutually exclusive.

```t
p = pipeline {
  -- Execute an external R script
  model = rn(script = "train_model.R", serializer = "pmml")

  -- Execute an external Python script
  predictions = pyn(script = "predict.py", deserializer = "pmml")

  -- Execute an external shell script
  report = shn(script = "postprocess.sh")

  -- node() auto-detects the runtime from the file extension
  summary = node(script = "summarise.R", serializer = "json")
}
```

When using `script`, the runtime is auto-detected from the file extension (`.R` → R, `.py` → Python, `.sh` → sh) if not explicitly set via the `runtime` argument. T reads the script file to extract identifier references, allowing the pipeline dependency graph to be built correctly from variables referenced in the external file.

### Shell / Bash nodes with `shn()`

Use `shn()` for pipeline steps that are easiest to express as shell or CLI commands. It is a convenience wrapper around `node(runtime = sh, ...)`, just like `rn()` and `pyn()` wrap `node()` for R and Python.

```t
p = pipeline {
  -- Exec-style shell node: command + positional argv
  fields = shn(
    command = "printf",
    args = ["first line\\nsecond line\\n"]
  )

  -- Script-style shell node: inline shell source executed with `sh`
  report = shn(command = <{
#!/bin/sh
set -eu

# Dependencies for T's lexical pipeline analysis: summary_r summary_py
printf 'R summary: %s\n' "$T_NODE_summary_r/artifact"
printf 'Python summary: %s\n' "$T_NODE_summary_py/artifact"
  }>)
}
```

There are two useful modes:

- **Exec mode**: provide a string `command` plus `args = [...]` to run a program directly with positional arguments.
- **Shell mode**: provide raw shell source with `<{ ... }>` or a `.sh` `script`, optionally overriding the interpreter with `shell = "bash"` and `shell_args = ["-lc"]` when you need Bash-specific syntax.

Shell nodes default to `serializer = text`, which makes them a good fit for reports, command output, and glue code between other pipeline nodes. For a full end-to-end example that mixes T, R, Python, and `sh`, see `tests/pipeline/polyglot_shell_pipeline.t` and `.github/workflows/polyglot-shell-pipeline.yml`.

### Fetching Remote Assets

Pipeline nodes can download files from URLs using `fetchurl`. This generates a Nix derivation that uses `builtins.fetchurl` with SHA-256 verification, making downloads reproducible and cached.

```t
-- Compute the hash upfront using prefetch:
hash = prefetch("https://example.com/data.csv")

-- Pin the hash in a pipeline node:
p = pipeline {
  raw = fetchurl("https://example.com/data.csv", sha256 = hash)
}

populate_pipeline(p, build = true)
pipeline_copy()

-- The downloaded file is at p.raw.path:
content = read_file(p.raw.path)
```

In REPL mode, `fetchurl` downloads immediately via `curl`:

```t
fetchurl("https://example.com/data.csv", output = "data.csv")
```

The companion function `prefetch(url)` downloads a URL and returns its SHA-256 hash, enabling the two-step workflow of computing the hash upfront then pinning it in a pipeline for reproducible builds.

### Setting Global Options for All Nodes

Use `set_pipeline_global_options` to share functions, includes, environment
variables, serializers, and other settings across every node in a pipeline
without repeating them per-node:

```t
p = pipeline {
  data = rn(<{ ... }>),
  model = pyn(<{ ... }>)
}
q = set_pipeline_global_options(p,
  functions = [rn: "utils.R", pyn: "preproc.py"],
  include = "shared/config.yaml",
  env_vars = [FOO: "bar"],
  serializer = ^json,
  noop = true
)
```

Per-node `functions` and `include` values are still applied after these globals.
If you pass the same runtime shorthand more than once (e.g. `[rn: "a.R", rn: "b.R"]`),
all values are concatenated — both files are included.

The merge strategy depends on the option:

- **Combine (prepend):** `functions`, `include`, `env_vars`, `args`, `shell_args`,
  `dependencies` — global values come first; per-node values follow. For dict
  options (`env_vars`, `args`), a per-node value for the same key wins.
- **Override:** `serializer`, `deserializer`, `shell`, `flake` — a provided global
  value replaces every node's per-node value entirely.
- **Force-only:** `noop` — `noop = true` forces every node to no-op; `noop = false`
  has no effect and cannot un-set a per-node `noop = true`.

#### Scoping Options to a Subset of Nodes

By default the settings are merged into every node. Pass `runtimes` and/or `nodes`
to restrict the merge to a subset; when both are given the target is their union:

```t
# Only R nodes get the arrow serializer
q1 = set_pipeline_global_options(p, runtimes = ["rn"], serializer = ^arrow)

# Only the named nodes become no-ops
q2 = set_pipeline_global_options(p, nodes = ["data"], noop = true)

# Union: the R nodes plus the "data" node
q3 = set_pipeline_global_options(p, runtimes = ["rn"], nodes = ["data"], noop = true)
```

Omitting the scoping arguments (or passing `na()`) targets every node; an explicitly
empty list (`nodes = []`) targets no nodes — the pipeline is returned unchanged.
An unmatched runtime or an unknown node name is an explicit `TypeError`.

#### Reading Back a Node's Resolved Configuration

Use `pipeline_node_options(pipeline, node)` to read back the fully resolved
configuration of a single node — including anything merged in by
`set_pipeline_global_options`:

```t
info = pipeline_node_options(q1, "data")
info.functions   # => function files merged into the node
info.noop        # => whether the node is a no-op
info.depth       # => topological depth in the DAG
```

##### The `provenance` Key

Every node tracks **where each resolved setting came from**. The returned dict
includes a `provenance` key with one entry per option:

- **Mergeable lists** (`functions`, `include`, `shell_args`, `dependencies`)
  are grouped as `{ global: [...], node: [...] }` — the global list holds
  values injected by `set_pipeline_global_options`, the node list holds values
  declared on the node itself (or set later via `mutate_node`).
- **Scalar overrides** (`serializer`, `deserializer`, `shell`, `flake`, `noop`)
  map to the source that won: `"global"` or `"node"`, or `NA` when unset.
- **Keyed options** (`env_vars`, `args`) map each individual key to its source.

```t
info = pipeline_node_options(q, "data")
info.provenance.functions.global   # => ["utils.R"] (injected globally)
info.provenance.functions.node     # => ["data.R"]  (declared on the node)
info.provenance.serializer         # => "global" or "node" or NA
```

This is the audit trail behind every resolved value: **what** the node uses is
in the top-level keys, **where it came from** is in `provenance`.

For a DataFrame-wide view across all nodes at once — e.g. "which nodes got
their serializer from global options?" — use `pipeline_config_to_frame(p)`
(see the [Advanced Pipeline Tutorial](advanced-pipeline-tutorial.md#node-metadata)).
`explain(p.node)` also includes a `config` section with this provenance.

See `set_pipeline_global_options` and `pipeline_node_options` in the
[API reference](api-reference.md) for the full key list.

---

## 5. Cross-Language Integration

T is designed to orchestrate code across multiple languages. The pipeline runner manages the serialization and deserialization of data between R, Python, and T using a first-class serializer system. For a deep dive into how T handles data interchange, see the [Serializers Documentation](serializers.md).

### Interchange Formats Comparison

| Format | Option | Best For | Requirement |
|---|---|---|---|
| **T Native** | `"default"` | T-to-T communication | None |
| **Arrow** | `"arrow"` | Large DataFrames | `pyarrow` (Py), `arrow` (R) |
| **PMML** | `"pmml"` | Predictive Models | `sklearn2pmml` (Py), `r2pmml` (R) |
| **JSON** | `"json"` | Simple lists/dicts | `jsonlite` (R) |

### Example: Training in R, Predicting in T

You can train a model in R and use T's native OCaml model evaluator to make predictions without leaving the T runtime:

```t
p = pipeline {
  -- Node 1: Train model in R using the rn wrapper
  model_r = rn(
    command = <{
      data <- read.csv("data.csv")
      lm(mpg ~ wt + hp, data = data)
    }>,
    serializer = "pmml"
  )
  
  -- Node 2: Predict in T using the R model
  predictions = node(
    command = <{
      test_df = read_csv("new_data.csv")
      predict(test_df, model_r)
    }>,
    runtime = "T",
    deserializer = "pmml"
  )
}
```

Setting `deserializer = "pmml"` on the T node tells the pipeline runner to use T's native PMML parser to convert the R model into a T model object.

---

## 6. Automatic Dependency Resolution

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

## 7. Chained Dependencies

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

## 8. Pipelines with Functions

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

## 9. Pipelines with Pipe Operators

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

## 10. Data Pipelines

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

## 11. Pipeline Introspection

> [↩ Quick Reference: Reading Node Artifacts](#pipeline-function-quick-reference)

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

### Explain diagnostics

`explain()` provides structured metadata about any value, including pipelines and nodes:

```t
p = pipeline { x = 10; y = x + 5; z = y * 2 }

e = explain(p)
e.kind        -- "pipeline"
e.node_count  -- 3

explain(p.x)  -- { `runtime`: "T", `kind`: "node", `name`: "x", ... }
```

---

## 12. Re-running Pipelines

Use `pipeline_run()` to re-execute a pipeline:

```t
p2 = pipeline_run(p)
p2.total  -- 30 (re-computed)
```

Re-running produces the same results — T pipelines are deterministic.

---

## 13. Deterministic Execution

Two pipelines with the same definitions always produce the same results:

```t
p1 = pipeline { a = 5; b = a * 2; c = b + 1 }
p2 = pipeline { a = 5; b = a * 2; c = b + 1 }
p1.c == p2.c  -- true
```

---

## 14. Error Handling & Resilience

### Errors are Values

In T, errors are **first-class values**. By default, evaluation is **resilient**: if a node fails, it produces an `Error` value instead of crashing the pipeline. This allows other independent nodes to continue building, giving you a full picture of which parts of your DAG are healthy.

```t
p = pipeline {
  a = 1 / 0      -- Produces an Error(DivisionByZero)
  b = 1 + 1      -- Still succeeds! (2)
  c = a + 1      -- Fails because 'a' is an error (Error)
}
```

When you print or build this pipeline, T provides a summary of which nodes succeeded and which failed.

### The `--failfast` Flag

If you prefer the usual, common behaviour where evaluation stops immediately at the first error, you can use the `--failfast` flag:

```bash
$ t run --failfast src/pipeline.t
```

In your T scripts, you can also opt-in to this behavior via `t_make()`:

```t
t_make(failfast = true)
```

### Cycle Detection

T detects circular dependencies and reports them at construction time, before any nodes are executed:

```t
pipeline {
  a = b
  b = a
}
-- Error(ValueError: "Pipeline has a dependency cycle involving node 'a'")
```

### Missing Nodes

Accessing a non-existent node returns a structured error:

```t
p = pipeline { x = 10 }
p.nonexistent
-- Error(KeyError: "node 'nonexistent' not found in Pipeline")
```

---

## 15. Materializing Pipelines

> [↩ Quick Reference: Reading Node Artifacts](#pipeline-function-quick-reference)

Defining a pipeline with `pipeline { ... }` evaluates nodes in-memory. To **materialize** them as reproducible Nix artifacts (potentially using R or Python dependencies you've defined in `tproject.toml`), use `populate_pipeline()` with the `build = true` argument:

```t
p = pipeline {
  data = read_csv("sales.csv")
  total = sum(data.$amount)
}

populate_pipeline(p, build = true)
```

`populate_pipeline(p, build = true)` is the primary command for materializing a pipeline. It does the following:

1. **Populates** the `_pipeline/` directory with `pipeline.nix` and `dag.json`.
2. **Generates** a Nix expression with one derivation per node. Crucially, if you define `[r-dependencies]` or `[py-dependencies]` in your `tproject.toml`, pipeline nodes have access to these language environments — including nodes that use a custom per-node flake (see [Custom Flakes per Node](pipeline-materialization.md#custom-flakes-per-node) for inheritance details).
3. **Triggers** a Nix build to materialize each node as a serialized artifact.
4. **Records** the build in a timestamped log file (`_pipeline/build_log_YYYYMMdd_HHmmss_hash.json`).

> [!NOTE]
> `build_pipeline(p)` is available as a shorthand for `populate_pipeline(p, build = true)`.

### Reading built artifacts

After building, use `read_node()` to retrieve materialized values:

```t
read_node(p.total)   -- reads the serialized artifact for "total"
```

These functions look up the node in the **latest build log** and deserialize the artifact.

---

## 16. Orchestrating with populate_pipeline()

For more control over the build process, T provides `populate_pipeline()`. This function prepares the pipeline infrastructure without necessarily triggering the Nix build immediately.

```t
populate_pipeline(p)                -- Prepares _pipeline/ only
populate_pipeline(p, build = true)  -- Same as build_pipeline(p)
```

> [!TIP]
> For advanced configuration and passing low-level arguments directly to the underlying Nix build system (such as concurrency, targeted nodes, custom binary caches, dry runs, and force rebuilds), see the comprehensive [Nix Build Options & Orchestration](nix-options.html) guide.

### The `_pipeline/` directory

T maintains a persistent state directory for your pipeline. When you populate or build, T creates:

- **`_pipeline/pipeline.nix`**: The generated Nix expression for your pipeline nodes.
- **`_pipeline/dag.json`**: A machine-readable dependency graph of your pipeline.
- **`_pipeline/build_log_*.json`**: History of previous successful builds.

---

## Best Practices

1. **Name nodes descriptively**: Use names like `raw_data`, `filtered_sales`, `summary_stats`
2. **Keep nodes focused**: Each node should do one thing
3. **Use pipes within nodes**: Combine pipeline structure with pipe operator for readability
4. **Inspect before consuming**: Use `pipeline_nodes()`, `pipeline_deps()`, and `pipeline_to_frame()` to understand pipeline structure
5. **Build incrementally**: Start with data loading, add transformations one node at a time
6. **Validate at construction time**: Use `pipeline_assert` at the end of a construction chain to catch structural errors early
7. **Separate data nodes from verification nodes**: Keep data transformation nodes (`serializer = ^csv`) separate from assertion check nodes. Verification nodes should return named dictionaries of `assert(expect_*(...))` calls (`serializer = ^json`) so that passing builds output a structured `{ check: true }` JSON artifact, while failing assertions immediately short-circuit to record detailed `AssertionError` tracebacks in the build log:
   ```t
   test_filter = pipeline {
     -- Transformation node
     filtered_data = node(
       command = data |> filter($score >= 88),
       serializer = ^csv,
       deserializer = ^csv
     )
     -- Verification node
     check_filter = node(
       command = [
         nrow_check: assert(expect_nrow(filtered_data, 2)),
         colnames_check: assert(expect_colnames(filtered_data, ["name", "score", "grade"]))
       ],
       serializer = ^json,
       deserializer = ^csv
     )
   }
   ```

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

---

## Next Steps

Now that you've mastered pipeline basics, explore advanced topics:

1. **[Advanced Pipeline Tutorial](advanced-pipeline-tutorial.md)** — Node manipulation, set operations, DAG transformations, composition, inspection, and validation.
2. **[Pipeline Materialization & Nix Orchestration](pipeline-materialization.md)** — Building pipelines into reproducible Nix artifacts, orchestrating builds, transferring archives, CI/CD, branching, and custom flakes.
3. **[Project Development](project_development.md)** — Master T's project structure and dependency management.
4. **[Package Development](package_development.md)** — Create reusable T libraries.
5. **[Reproducibility Guide](reproducibility.md)** — Deep dive into T's commitment to reproducible research.
6. **[API Reference](api-reference.md)** — Complete function reference by package.
