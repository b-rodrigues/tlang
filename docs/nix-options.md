# Nix Build Options & Orchestration

> Passing low-level Nix configuration and arguments directly to the T pipeline builders

T integrates declaratively with the Nix ecosystem to compile, build, and run pipelines in completely isolated, reproducible sandboxes. To offer fine-grained control over Nix builds, T provides a unified `nix_options` dictionary argument. 

This argument is accepted by all primary orchestration and execution entry points:
- `populate_pipeline()`
- `build_pipeline()`
- `pipeline_run()`
- `t_make()`

---

## The `nix_options` Dictionary

Instead of cluttering functions with flat parameters, all low-level Nix build and resource limits are grouped under a single, optional `nix_options` dictionary:

```t
nix_options = [
  max_jobs: 4,
  max_cores: 2,
  dry_run: true,
  force: true,
  targets: ["filtered_data"],
  cache: "rstats-on-nix",
  builders: "ssh://builder.example.com",
  keep_env: ["API_KEY", "ACCESS_TOKEN"],
  sandbox: "relaxed"
]
```

### Supported Parameters

| Parameter | Type | Command Line Equivalence | Description |
| :--- | :--- | :--- | :--- |
| `max_jobs` | `Int` | `--max-jobs <N>` | The maximum number of build jobs Nix is allowed to run in parallel. Must be greater than `0`. |
| `max_cores` | `Int` | `--cores <N>` | The maximum number of CPU cores that Nix will assign per build job. Must be greater than `0` (or `0` to use all available cores). |
| `dry_run` | `Bool` | `--dry-run` | When `true`, Nix plans the build actions instead of executing them. Returns a planned DataFrame (see details below). |
| `force` | `Bool` | `--check` | When `true`, forces Nix to rebuild the specified nodes even if they already exist in the cache. |
| `targets` | `String` or `List[String]` | `-A <target>` | Limits execution or building to specific node name(s) and their upstream dependencies. |
| `cache` | `String` | `--option extra-substituters ...` | Sets a custom Cachix cache repository name (e.g. `"my-cache"` maps to `https://my-cache.cachix.org`). |
| `builders` | `String` | `--builders <uri>` | Configures Nix remote build machines (e.g. `"ssh://builder.example.com"`). |
| `keep_env` | `String` or `List[String]` | `--option keep-env ...` | Whitelists specific environment variables to forward into the Nix sandbox. |
| `sandbox` | `Bool` or `String` | `--option sandbox <strict|relaxed|false>` | Controls Nix sandboxing mode: `relaxed`, `strict` (or `true`), `none` (or `false`). |

---

## 1. Dry Runs and planned DataFrames

Passing `dry_run: true` instructs Nix to query the derivation graph and compute build and binary cache fetch actions without actually running any code.

In T, this is a first-class operation: instead of dumping text to stdout, `build_pipeline()` and `pipeline_run()` in dry-run mode return a structured T **DataFrame** outlining the planned build graph:

```t
p = pipeline {
  raw = read_csv("data.csv")
  filtered = raw |> filter($age > 30)
}

-- Trigger a planned dry-run
plan_df = build_pipeline(p, nix_options = [dry_run: true])
print(plan_df)
```

The returned DataFrame contains three columns:
- **`node`**: The name of the pipeline node.
- **`action`**: The build action determined by Nix (`"build"`, `"fetch"` from cache, or `"noop"`).
- **`path`**: The absolute `/nix/store/` path where the node's output derivation resides.

This allows you to programmatically inspect build plans, perform capacity planning, or check whether specific nodes will be pulled from a binary cache before initiating a build.

---

## 2. Targeting Specific Nodes

For large pipelines with many expensive nodes, you can run and materialize only a subset of nodes by defining `targets` inside `nix_options`:

```t
-- Rebuild only the "filtered" node and its upstream dependencies
build_pipeline(p, nix_options = [
  targets: ["filtered"],
  force: true
])
```

The pipeline runner parses `targets` (which can be a single String or a List/Vector of Strings), ensures they match valid node identifiers in the DAG, and appends the appropriate `-A` flags during the `nix-build` invocation.

---

## 3. High-level CLI Orchestration via `t_make`

The high-level CLI and REPL builder, `t_make()`, also supports the `nix_options` dictionary, accepting it as either a named parameter or as the second positional argument:

```t
-- In the REPL: Run the pipeline with parallel execution limits
t_make(nix_options = [max_jobs: 4, max_cores: 2])

-- Positional signature: t_make(filename, nix_options, verbose, failfast)
t_make("src/pipeline.t", [max_jobs: 8])
```

---

## 4. Remote Builders (`builders`)

Offloading computationally intensive pipeline tasks (such as deep learning models or high-dimensional matrix operations) to high-performance remote builders or GPU clusters is fully supported using standard Nix remote builders:

```t
-- Run the pipeline but offload the build derivations to remote machines
pipeline_run(p, nix_options = [
  builders: "ssh://gpu-builder.local x86_64-linux /root/.ssh/id_rsa 16 1 kvm,benchmark - -"
])
```

The `builders` parameter accepts a string formatted according to standard Nix remote builders syntax (`ssh://<host> <system-types> <ssh-key-path> <max-jobs> <features>`). Multiple builders can be provided by separating them with a newline character.

---

## 5. Sandboxing Control (`sandbox`)

By default, Nix runs all build jobs inside highly isolated environments. While this guarantees 100% reproducibility, certain legacy tasks or developer workflows may require relaxing sandboxing constraints:

```t
-- Relax sandboxing to allow local resource access for specific nodes
build_pipeline(p, nix_options = [
  sandbox: "relaxed"
])

-- Fully disable sandboxing (not recommended for production)
pipeline_run(p, nix_options = [
  sandbox: false -- maps to sandbox: "none"
])
```

Supported values for `sandbox`:
- `true` or `"strict"`: All build jobs are completely isolated (default).
- `"relaxed"`: Relaxes sandboxing rules for derivations that request it, allowing paths in the host filesystem to be accessed.
- `false` or `"none"`: Sandboxing is disabled entirely.

---

## 6. Environment Whitelisting (`keep_env`)

To protect the purity and reproducibility of your builds, Nix purges all host environment variables by default. If your pipeline steps require access to specific host environment variables (such as access tokens, private database connection URIs, or licensing keys), you can pass-through these variables using `keep_env`:

```t
-- Pass-through specific environment variables into the build sandbox
t_make(nix_options = [
  keep_env: ["GITHUB_TOKEN", "DB_CONNECTION_STRING"]
])

-- Single variable pass-through
pipeline_run(p, nix_options = [
  keep_env: "AWS_ACCESS_KEY_ID"
])
```

The pipeline engine validates that only allowed variables are whitelisted and safely passes them to the Nix builder, keeping all other host details hidden.

---

## 7. Strong Validation

T enforces strict validation at pipeline construction time. Providing an unrecognized option or an invalid type inside the `nix_options` dictionary will raise a structured `TypeError` or `ValueError`:

```t
-- ❌ TypeError: t_make: 'max_jobs' in nix_options must be an Int
t_make(nix_options = [max_jobs: "high"])

-- ❌ TypeError: t_make: unknown option 'threads' in nix_options
t_make(nix_options = [threads: 4])

-- ❌ ValueError: sandbox: 'invalid_sandbox' is not a valid sandboxing mode
t_make(nix_options = [sandbox: "invalid_sandbox"])
```

---

## 8. Low-Level Derivation Projection (`pipeline_to_drv`)

For static analysis, auditing, and deep debugging, you can introspect the raw Nix store derivation `.drv` paths generated for each node without running the actual build tasks:

```t
-- Get raw Nix store derivation paths for all pipeline nodes
drvs = pipeline_to_drv(p)

-- Returns a dictionary mapping node names to their store paths:
-- {
--   "node_a": "/nix/store/a1b2c3d4...-node_a.drv",
--   "node_b": "/nix/store/x9y8z7w6...-node_b.drv"
-- }
```

By querying the `.drv` path, developers can perform low-level audits, inspect generated Nix environments, or run `nix derivation show` to analyze precise inputs and environment configurations.

