# Pipeline Materialization & Nix Orchestration

> Building pipelines into reproducible Nix artifacts, orchestrating builds, transferring archives, and customizing build environments

This guide covers how pipelines are *materialized* — turned into reproducible Nix derivations and artifacts — and how to orchestrate that process. It builds on the [Pipeline Tutorial](pipeline_tutorial.md) (basics) and the [Advanced Pipeline Tutorial](advanced-pipeline-tutorial.md) (pipeline manipulation and composition).

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
  node_a = node(command = 100, serializer = ^json)
  
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
- `action`: The action planned (e.g., `"rebuild"`, `"fetch"`, or `"cache_hit"`).
- `store_path`: The absolute store path of the Nix derivation or artifact.

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
-- Returns a DataFrame with columns: node, action, and store_path.
-- "action" will be one of:
--   - "cache_hit": path is already built/cached locally
--   - "rebuild": path must be rebuilt locally
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

### 35.1 `map_pattern` — One Branch Per Element

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

### 35.2 `cross_pattern` — Cartesian Product

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

### 35.3 DataFrame Row Branching

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

### 35.4 Selector Patterns

For finer-grained control over which elements produce branches, use selector patterns.
All four take exactly one dependency and an integer parameter, and produce N branches
where N is determined by the parameter.

#### 35.4.1 `slice_pattern(dep, [i, j, ...])` — Branch on Specific Indices

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

#### 35.4.2 `head_pattern(dep, n)` — Branch on First N Elements

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

#### 35.4.3 `tail_pattern(dep, n)` — Branch on Last N Elements

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

#### 35.4.4 `sample_pattern(dep, n)` — Randomly Select N Elements

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

### 35.5 Pattern Branching with Non-T Runtimes

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

See §35.8 for a complete polyglot example using `cross_pattern` and `map_pattern` with R `ggplot2`.

### 35.6 Writing the Expanded Pipeline to a File

Pass `to_script` to write the expanded pipeline as a T source file for inspection or debugging:

```t
expand_pipeline(p, to_script = "expanded_pipeline.t")
```

The output file contains the full `pipeline { ... }` definition with all branches unrolled.

### 35.7 Build and Composition Auto-Expand

`populate_pipeline()`, `build_pipeline()`, `chain()`, `parallel()`, `union()`, `intersect()`, `difference()`, and `patch()` all automatically expand any unexpanded patterns in their pipeline inputs before proceeding. You only need to call `expand_pipeline()` explicitly when you want to inspect the branch structure before building.

### 35.8 Lazy Branch Access

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

### 35.9 Complete Example: Polyglot Dynamic Branching Pipeline

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

## 37. Custom Flakes per Node

By default, every node in a pipeline uses the project's flake (defined by `tproject.toml`) for its build environment. The **`flake`** named argument lets you override this — each node can use a completely different Nix flake, replacing the entire environment for that node.

```t
p = pipeline {
  -- Node using the default project flake (unchanged)
  a = node(command = "hello from default flake", runtime = T)

  -- Node using a different flake from GitHub
  b = node(
    command = "hello from custom flake",
    runtime = T,
    flake = "github:b-rodrigues/tlang"
  )
}
```

### How It Works

When `populate_pipeline(p)` generates the Nix expression, each unique flake path creates a dedicated environment via the `mkNodeEnv` helper:

```nix
env_github_b_rodrigues_tlang = mkNodeEnv "github:b-rodrigues/tlang";
env_github_jbedo_rshells     = mkNodeEnv "github:jbedo/rshells";
env_path_test_flake           = mkNodeEnv "path:../test_flake";
```

Nodes referencing a custom flake are rewritten to use that flake's bindings (`env_<name>.stdenv`, `env_<name>.tBin`, etc.) instead of the project-level bindings. Nodes without a `flake` argument continue to use the project flake unchanged.

### Supported Flake References

| Format | Example | Notes |
|--------|---------|-------|
| `github:owner/repo` | `github:b-rodrigues/tlang` | GitHub repository |
| `github:owner/repo/rev` | `github:b-rodrigues/tlang/main` | With branch/commit |
| `gitlab:owner/repo` | `gitlab:example/project` | GitLab repository |
| `sourcehut:owner/repo` | `sourcehut:~user/project` | SourceHut repository |
| `path:/abs/path` | `path:/home/user/myflake` | Absolute local path |
| `path:../relative/path` | `path:../test_flake` | Relative local path |

### Selective Replacement with Fallback

A per-node flake **replaces** the project flake for that node on a per-component basis. Each runtime component is resolved independently from the custom flake when available, otherwise it falls back to the project-level binding:

| Component | Resolved from custom flake if… | Falls back to project if missing |
|-----------|-------------------------------|----------------------------------|
| `tBin` (T binary) | `flake.inputs.t-lang.packages.${system}.default` | Project `t` binary |
| `r-env` (R environment) | `flake.inputs.t-lang.packages.${system}.tlang-r` | Just `pkgs.rWrapper` (no `tlang-r`) |
| `tlangJl` (Julia path) | `flake.inputs.t-lang.packages.${system}.tlang-julia-path` | Project Julia path |
| `pkgs` (nixpkgs) | `flake.legacyPackages.${system}` or `flake.inputs.nixpkgs.legacyPackages.${system}` | Project nixpkgs |
| `stdenv` | `pkgs.stdenv` from the custom flake's nixpkgs | — (derives from `pkgs`) |
| `py-env` (Python) | `pkgs.${pyVersion}.withPackages` from custom nixpkgs | — (just the packages, no `t-lang` component) |
| `juliaPkg` (Julia) | `pkgs.${juliaPackageName}` from custom nixpkgs | — (just the package, no `t-lang` component) |

This means:

- **An R-only flake** (like `github:jbedo/rshells`) provides R packages and nixpkgs snapshot, while T serialization infrastructure comes from the project
- **A full t-lang flake** (like `github:b-rodrigues/tlang`) replaces everything — nixpkgs, R/Python/Julia, and T binary
- **Different nixpkgs version** — a node can use an older or newer nixpkgs than the project
- **Different R/Python packages** — each node can have its own package set
- **Different t-lang version** — each node can run a different build of T (if the flake provides `t-lang`)

### Project-Level Package Inheritance

A per-node flake replaces the **runtime components** (t-lang binary, language runtimes, nixpkgs) for that node. However, **project-level package declarations** from `tproject.toml` (`[r-dependencies]`, `[py-dependencies]`, `[jl-dependencies]`) are still installed in every node, including those using a custom flake. The flake determines *which nixpkgs revision* the packages are built from, but `tproject.toml` determines *what packages* are installed on top of the flake's environment.

This means:

- **Same package, different nixpkgs** — A package declared in `[r-dependencies]` is built from each per-node flake's nixpkgs. A node using `nixpkgs/r-updates` may get a different version than a node using `nixos-24.11`.
- **Project-level convenience** — Common packages can be declared once in `tproject.toml` and shared across all nodes, regardless of which flake each node uses.
- **Self-contained flakes** — If you need a flake to be fully self-contained (usable in any project without modifying `tproject.toml`), configure the desired packages directly within the flake's R/Python/Julia environment rather than relying on project-level declarations.

```t
-- Example: both nodes use different flakes, but both inherit jsonlite
-- from the project's [r-dependencies]:
f = node(
  command = <{ library(jsonlite); toJSON(mtcars) }>,
  runtime = R,
  flake = "github:jbedo/rshells"
)
g = node(
  command = <{ library(jsonlite); fromJSON("data.json") }>,
  runtime = R,
  flake = "path:../minimal_r_flake"
)
```

> [!TIP]
> To check which packages a per-node flake environment has access to, use `require()` in R or `import` in Python/Julia within the node's command block rather than assuming the flake's nixpkgs determines package availability.

### Local Flakes

You can reference a local flake directory using `path:` URLs. The path is resolved relative to the `_pipeline/` directory where the Nix expression is generated:

```t
d = node(
  command = "hello from local flake",
  runtime = T,
  flake = "path:../test_flake"
)
```

The referenced directory must contain a valid `flake.nix` with `inputs.nixpkgs` and the standard t-lang `packages` (including `tlang-r`, `tlang-julia`, etc.) for proper sandbox resolution.

### How the Flake Must Be Structured

To work with `mkNodeEnv`, the custom flake must expose the same outputs that T's project flake provides:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    t-lang.url  = "github:b-rodrigues/tlang";
  };

  outputs = { self, nixpkgs, t-lang }: {
    legacyPackages.${builtins.currentSystem} =
      nixpkgs.legacyPackages.${builtins.currentSystem};

    packages.${builtins.currentSystem} = rec {
      default          = t-lang.packages.${builtins.currentSystem}.default;
      tlang-r          = t-lang.packages.${builtins.currentSystem}.tlang-r;
      tlang-julia-path = t-lang.packages.${builtins.currentSystem}.tlang-julia-path;
      "tlang-julia"    = t-lang.packages.${builtins.currentSystem}."tlang-julia";
    };
  };
}
```

The key requirements are:

- `legacyPackages.${system}` — provides the full nixpkgs package set
- `packages.${system}.default` — provides the `t` binary
- `packages.${system}.tlang-r` — provides R packages declared in the flake
- `packages.${system}.tlang-julia-path` / `packages.${system}."tlang-julia"` — provides Julia packages

If these outputs are missing, the per-node sandbox will fail at build time when attempting to resolve runtime dependencies.

### Backward Compatibility

Nodes without a `flake` argument are completely unaffected. The project-level environment is aliased (`stdenv = projectStdenv`, `tBin = projectTBin`, etc.) so existing pipeline definitions require no changes.

---

## Next Steps

Now that you've mastered pipeline materialization, learn how to manage reproducible projects and develop T packages:

1. **[Advanced Pipeline Tutorial](advanced-pipeline-tutorial.md)** — Node manipulation, set operations, DAG transformations, composition, and validation.
2. **[Project Development](project_development.md)** — Master T's project structure and dependency management.
3. **[Package Development](package_development.md)** — Create reusable T libraries.
4. **[Reproducibility Guide](reproducibility.md)** — Deep dive into T's commitment to reproducible research.
5. **[API Reference](api-reference.md)** — Complete function reference by package.
