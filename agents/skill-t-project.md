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

## Common mistakes

- **Reassigning a variable with `=`:** T is immutable. Use `:=` to rebind, or give the new value a new name. E.g., `a = 1; a = 2` is invalid.
- **Writing a `for` loop:** Loops do not exist in T. Use `map()`, `summarize()`, or a colcraft verb.
- **Referencing a column as a bare name inside a colcraft verb:** E.g., `filter(df, amount > 0)` is invalid. It must be `filter(df, $amount > 0)`. The `$` is required for NSE.
- **Writing output to `data/`:** Treat it as read-only. Pipeline outputs must go through `pipeline_copy(p, node, to)` into `outputs/`.
- **Skipping the `pipeline { ... }` wrapper:** A bare script of T statements cannot run. Everything reproducible must be a node inside a pipeline.

## Never do this

- Call `install.packages()` or `pip install`.
- Write intermediate CSV files between nodes.
- Create multiple `pipeline { }` blocks in a single script.
- Guess stdlib function signatures.
- Bypass `tproject.toml` dependencies.

## Debugging and inspecting a node/pipeline

0. **Quick structural check:** Run `t check --schema src/pipeline.t` for instant validation without Nix builds. Catches dependency cycles, missing columns, and `expect()` contract violations in seconds. Use `--watch` for continuous feedback during development.
1. **Check pipeline status:** Use `inspect_pipeline(p)` to view node build states, cache locations, and execution times.
2. **Examine evaluated data:** Use `read_node(p.name)` from the REPL/subshell to read and inspect the actual output of a built node.
3. **Read diagnostic logs:** `t explain --node <name>` from the shell, or `explain(read_node(p.name))` from the REPL — the `diagnostics` field tells you what actually ran and what it produced.
4. **Resilient errors:** If a node errors, check `is_error()` on its output. T nodes return `Error` values rather than raising OCaml exceptions, so a run can complete while carrying an error downstream.
5. **Nix env check:** `t doctor` catches environment drift (stale flake, missing Nix inputs) before you debug code.

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
- If you touched `tproject.toml`, you ran `t update` afterward.
- If the project already uses `intent { ... }` blocks, continue that convention when making analytical decisions.
