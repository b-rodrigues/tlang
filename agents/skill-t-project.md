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

## Debugging and inspecting a node/pipeline

0. **Quick structural check:** Run `t check --schema src/pipeline.t` for instant validation without Nix builds. Catches dependency cycles, missing columns, and `expect()` contract violations in seconds. Use `--watch` for continuous feedback during development.
1. **Check pipeline status:** Use `inspect_pipeline(p)` to view node build states, cache locations, and execution times.
2. **Examine evaluated data:** Use `read_node(p.name)` from the REPL/subshell to read and inspect the actual output of a built node.
3. **Read diagnostic logs:** `t explain --node <name>` from the shell, or `explain(read_node(p.name))` from the REPL — the `diagnostics` field tells you what actually ran and what it produced.
4. **Resilient errors:** If a node errors, check `is_error()` on its output. T nodes return `Error` values rather than raising OCaml exceptions, so a run can complete while carrying an error downstream.
5. **Nix env check:** `t doctor` catches environment drift (stale flake, missing Nix inputs) before you debug code.
6. **Non-pipeline scripts:** Scripts without a `pipeline { }` block need `t run --unsafe` (e.g., `t run --unsafe src/view.t`).
7. **`read_node` requires dot access:** Use `read_node(p.node_name)` — the string form `read_node("name")` was an intentional breaking change and throws a TypeError. To read from past builds, use `read_past_node(p.node_name, which_log = "...")`.

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
then apply with `t fix`. Supported fix types:
- `Cast` — inserts a type coercion (`mutate($col = as.double($col))`)
- `Rename_column` — renames `$old` to `$new` in column references
- `Add_node_arg` — adds a missing argument to a node definition

**After `t run`:** Run `t diff` to see what changed. This is free (uses Nix content
hashes) and tells you whether your edit had the intended effect or cascaded downstream.

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
- If pipeline nodes declare `expect()` contracts, the schema check confirms they hold.
- `t run src/pipeline.t` (or the project's entry pipeline) completes without an unhandled `Error`.
- `t diff src/pipeline.t` shows only the nodes you intended to change (no unexpected cascades).
- If you touched `tproject.toml`, you ran `t update` afterward.
- If the project already uses `intent { ... }` blocks, continue that convention when making analytical decisions.
