---
name: t-project
description: Use this skill when working inside a T (tlang) analysis project — a directory with tproject.toml and pipeline .t scripts. Trigger for writing or editing pipeline { ... } blocks, adding or debugging nodes (node/rn/pyn/jln/shn), working with colcraft verbs ($col, filter, mutate, summarize), wiring R/Python/Shell/Julia code into a pipeline, or running/updating a T project (t run, t update, t test, t doctor). Trigger even if the user just says "add a step" or "the pipeline is broken" without mentioning T by name — if the directory has tproject.toml, this is a T project.
---

# T Project Quickstart

This is a companion to `AGENTS.md` and `T-LANGUAGE-REFERENCE.md` in this project's root. This skill covers the procedural playbook for common pipeline tasks.

## Before writing or modifying T code

1. Read `T-LANGUAGE-REFERENCE.md` in the project root.
2. Do not guess stdlib APIs or function signatures.
3. If the reference conflicts with prior assumptions, follow the reference.

## Choosing a node type

Pick based on what language executes the code inside:

| You want to... | Use |
|---|---|
| Run a pure T expression (filter, mutate, join) | `node(command = <t-expr>, runtime = T)` |
| Run R code (a model, a plot, a stats package) | `rn(...)` |
| Run Python code (ML, a specific library) | `pyn(...)` |
| Run Julia code (numerical computing, models) | `jln(...)` |
| Shell out (rsync, a CLI tool, a compiled binary) | `shn(...)` |

Tabular outputs use Arrow by default (`serializer = ^arrow`). Do not serialize through CSV unless the user explicitly requests it.

## Fetching remote assets

Use `fetchurl()` to download files during pipeline builds. The file is stored in a Nix
store path and read via dependency injection — do NOT read the file inside your pipeline block.

### Text content (HTML, JSON, plain text)

```t
hash = prefetch(url)
...
data = fetchurl(url, sha256 = hash, serializer = ^text)
```

Use `serializer = ^text` when downstream nodes need the content as a string (e.g., for
BeautifulSoup, JSON parsing). The default is `^bin` (binary).

### Binary content (Excel, Parquet, etc.)

```t
hash = prefetch(url)
...
data = fetchurl(url, sha256 = hash)
```

### Accessing fetchurl output

- **Via dependency injection:** Pass `fetchurl` nodes as upstream deps. The content is
  injected as a variable (string for `^text`, file path for `^bin`).
- **Via path:** Use `p.node_name.path` to get the Nix store path after build.

### Multiple fetchurl deps with different serializers

When a node depends on multiple `fetchurl` nodes with different serializers, use a
dictionary deserializer:

```t
parse = pyn(
  command = <{ ... }>,
  deserializer = [ fetch_html: ^text, fetch_json: ^text ],
  serializer = ^csv
)
```

### Gotchas

- `prefetch(url)` runs **outside** the pipeline (before `pipeline { }`). It computes
  the SHA256 hash. You must commit this hash — it's part of the reproducible build.
- The `^text` serializer emits a warning about "custom or unknown strategy". This is
  expected and safe to ignore.
- Do NOT use `read_node()` inside a pipeline block to read fetchurl output. Use
  dependency injection (variable name) or `p.node_name.path` after build.
- **Python text deserializer:** The Nix emitter template wraps deserializers in
  `%(artifact_path)`, so `lambda path: open(path).read()` produces
  `lambda path: open(path).read()(artifact_path)` — Python parses this as the full
  lambda body, and the lambda is never invoked. Use `open` directly instead.

## Common mistakes

- **Reassigning a variable with `=`:** T is immutable. Use `:=` to rebind, or give the new value a new name. E.g., `a = 1; a = 2` is invalid.
- **Writing a `for` loop:** Loops do not exist in T. Use `map()`, `summarize()`, or a colcraft verb.
- **Referencing a column as a bare name inside a colcraft verb:** E.g., `filter(df, amount > 0)` is invalid. It must be `filter(df, $amount > 0)`. The `$` is required for NSE.
- **Adding trailing commas after nodes in `pipeline { }`:** Pipeline nodes are separated by newlines or semicolons, NOT commas. A trailing comma causes a parse error. `t check` will report: "Unexpected ',' in pipeline block."
- **Writing output to `data/`:** Treat it as read-only. Pipeline outputs must go through `pipeline_copy(p, node, to)` into `outputs/`.
- **Skipping the `pipeline { ... }` wrapper:** A bare script of T statements cannot run. Everything reproducible must be a node inside a pipeline.
- **Writing to `/tmp` or absolute paths from nodes:** Nodes run inside a hermetic Nix sandbox with a read-only filesystem. For debugging, create a view script (`src/view.t`) that uses `t_make()` + `read_node(p.name)` + `glimpse()` to inspect node outputs.

## Never do this

- Call `install.packages()` or `pip install`.
- Write intermediate CSV files between nodes.
- Create multiple `pipeline { }` blocks in a single script.
- Guess stdlib function signatures.
- Bypass `tproject.toml` dependencies.
- Use `read_node("node_name")` — the string form was removed. Only `read_node(p.node_name)` works.

## Node Inspection Playbook

Use this workflow to understand what a pipeline node does, what it produced, and whether anything went wrong. Start broad, then drill in.

### Quick reference

| Function | What it tells you | When to use |
|---|---|---|
| `inspect_pipeline(p)` | DataFrame: node, runtime, serializer, deps, has_script | First look — understand pipeline structure |
| `inspect_node(p.node)` | Dict: name, runtime, path, serializer, class, dependencies, warnings | Drill into one node's metadata |
| `read_node(p.node)` | The actual data (DataFrame, list, string, etc.) | Load and examine the node's output |
| `warning_msg(p.node)` | Formatted warning text (own + upstream) | Diagnose warnings without raw diagnostics |
| `explain(read_node(p.node))` | Structured dict of the value's type, shape, columns, preview | Understand what the data looks like |
| `rebuild_node(p.node)` | Rebuilds a single node, returns updated ComputedNode | One node changed, don't rebuild entire pipeline |
| `debug_node(p.node)` | Launches interactive REPL in the node's runtime env | Deep debugging of R/Python/Julia code |

### Typical agent workflow

```t
# 1. See the whole pipeline at a glance
inspect_pipeline(p)

# 2. Pick a node and check its metadata
inspect_node(p.clean_data)

# 3. Load the actual data
read_node(p.clean_data)

# 4. Inspect the shape and contents
explain(read_node(p.clean_data))

# 5. Check for warnings
warning_msg(p.clean_data)
```

### From the shell (no REPL needed)

```bash
# Structural check (milliseconds, no Nix builds)
t check --schema src/pipeline.t

# Explain a specific node's diagnostics (use --json for agent-readable output)
t explain --node p.clean_data
t explain --json --node p.clean_data

# Catch environment drift
t doctor
```

### Gotchas

- **`read_node` requires dot access:** Use `read_node(p.node_name)` — the string form `read_node("name")` throws a TypeError.
- **`t explain --node` requires explicit prefix:** You must specify `t explain --node <pipeline_var>.<node_name>` (e.g. `p.clean_data`). Omitting the prefix or using a non-existent variable name will result in an error.
- **`read_node` before build:** If the pipeline hasn't been built, `read_node` errors. Use `build_pipeline(p)` first, or `read_past_node(p.node_name, which_log = "...")` for historical builds.
- **Non-pipeline scripts:** Scripts without a `pipeline { }` block need `t run --unsafe` (e.g., `t run --unsafe src/view.t`).
- **Resilient errors:** T nodes return `Error` values rather than raising exceptions. A run can complete while carrying an error downstream. Check `is_error()` on outputs.
- **Warning suppression:** Use `suppress_warnings()` at the end of a node definition to silence known warnings.
- **Use `nix develop` first:** Always run `nix develop` (or `nix develop -c <command>`) to enter the T environment. Without it, `t`, R, Python, and Julia with tlang packages are not available.
- **Inspect from R/Python/Julia directly:** The companion packages (`tlang` in R, `tlang` in Python, `Tlang` in Julia) expose `read_node()`, `inspect_node()`, and `inspect_pipeline()`. If you need to explore a node's contents interactively, it can be easier to load the data in R/Python/Julia than in the T REPL — especially for plotting, statistical summaries, or DataFrame manipulation. For example: `nix develop -c R -e 'library(tlang); p <- readRDS("pipeline.rds"); glimpse(read_node(p.clean_data))'`.

## Development workflow: check, fix, build, diff

T's feedback loop is tiered: cheap checks first, expensive builds last. Always follow this order:

```
1. t check --schema pipeline.t    ← milliseconds, no Nix. Catches structural + schema errors.
2. t fix --dry-run pipeline.t     ← preview mechanical fixes (Cast, Rename_column, Add_node_arg).
3. t fix pipeline.t               ← apply fixes (only if dry-run looks right).
4. t check --schema pipeline.t    ← re-validate after fixes.
5. t run pipeline.t               ← NOW trigger the Nix build. Only invalidated nodes rebuild.
6. t diff pipeline.t              ← confirm blast radius: which nodes actually changed?
```

**Why this order matters:** `t check` costs milliseconds. `t run` costs minutes (Nix
builds Python/R/Julia environments per node). Never trigger `t run` until `t check`
passes clean — you're wasting minutes on errors that could be caught in seconds.

**When `t check --json` emits a `suggested_fix`:** Preview it with `t fix --dry-run`,
then apply with `t fix`. Supported fix types carry a `confidence` field (`"high"`, `"medium"`, or `"low"`) indicating whether the fix is highly deterministic or heuristic:
- `Cast` (High confidence) — inserts a type coercion (`mutate($col = as.double($col))`)
- `Rename_column` (High confidence) — renames `$old` to `$new` in column references
- `Add_node_arg` (Medium confidence) — adds a missing argument (e.g. deserializer) to a node definition
- `Suggest_identifier` (Medium confidence) — suggests spelling corrections for names
- `Run_command` (Low confidence) — suggests shell commands

### ⚠️ Critical Rules for Agentic Check-Fix Loops

1. **`t fix` is Not Idempotent:** `t fix` will mechanically insert code even if a identical correction was already applied in a previous step. You must re-run `t check` after every `t fix` and monitor the error count. If the error count does not decrease, **stop immediately** and do not run `t fix` again, otherwise you will corrupt the file.
2. **Never Use `--watch`:** Running `t check --watch` will start an infinite loop monitoring file changes, which blocks execution and hangs the agent.
3. **Schema Silencing on Unrecognized Verbs:** If the pipe chain uses a custom/unrecognized function (i.e. not standard `select`, `filter`, `mutate`, `arrange`, etc.), the schema compiler drops the schema to empty (`[]`). This disables subsequent column-reference checks downstream. Always verify column references manually when custom functions are introduced.

**After `t run`:** Run `t diff` (or `t diff --json` for structured agent output) to see what changed. This is free (uses Nix content hashes) and tells you whether your edit had the intended effect or cascaded downstream.

**`t check --schema` limitation:** This validates structure and type contracts in milliseconds, but does NOT build the pipeline. Calls to `read_node()` in post-build sections will error during `t check` — these are expected. Verify with `t run` instead.

## Worked example: adding a node

When adding a node to an existing pipeline, write:

```t
model = rn(
  command = <{ fixest::feols(amount ~ x1 + x2, data = clean) }>,
  deps = [clean],
  serializer = ^arrow
)
```

Notes:
- Prefer one transformation per node.
  - **Good:** `read -> clean -> model`
  - **Avoid:** `read -> clean -> feature engineer -> model`
- Always place new nodes inside the existing `pipeline { ... }` block.
- `deps = [clean]` makes the upstream node's output available to the R code as `clean`.

**Accessing upstream data:** Inside `<{ }>` blocks, upstream node outputs are available as variables by their node name. Do NOT use `read_node()` inside node code — T automatically deserializes and injects the data:

```t
clean_data = rn(
  command = <{
    # 'read_excel' is available as a data.frame automatically
    read_excel |>
      standardize_locality() |>
      filter_commune_level()
  }>,
  functions = ["src/functions.R"],
  deserializer = ^csv,
  serializer = ^csv
)
```

## Design principles

When modifying a pipeline:
- Preserve reproducibility.
- Preserve incremental caching.
- Preserve language independence.
- Prefer explicit dependencies.
- Prefer many small nodes over large nodes.
- Keep raw data immutable.

## Before calling a task done

- `t check --schema src/pipeline.t` passes with no errors or warnings.
- `t run src/pipeline.t` (or the project's entry pipeline) completes without an unhandled `Error`.
- `t diff src/pipeline.t` shows only the nodes you intended to change (no unexpected cascades).
- If you touched `tproject.toml`, you ran `t update` afterward.
- If the project already uses `intent { ... }` blocks, continue that convention when making analytical decisions.
