---
name: t-project
description: Use this skill when working inside a T (tlang) analysis project — a directory with tproject.toml and pipeline .t scripts. Trigger for writing or editing pipeline { ... } blocks, adding or debugging nodes (node/rn/pyn/shn), working with colcraft verbs ($col, filter, mutate, summarize), wiring R/Python/Shell code into a pipeline, or running/updating a T project (t run, t update, t test, t doctor). Trigger even if the user just says "add a step" or "the pipeline is broken" without mentioning T by name — if the directory has tproject.toml, this is a T project.
---

# T Project Quickstart

This is a companion to `AGENTS.md` and `T-LANGUAGE-REFERENCE.md`, which already live in this
project's root — read both before writing code if you haven't. This skill covers the *how*, not
the *what*: the concrete moves that come up in almost every T pipeline task.

## Before touching anything

Read `T-LANGUAGE-REFERENCE.md` in the project root. It's tiered to this project's context level
and is the source of truth for exact function signatures — don't guess at stdlib arguments.

## Choosing a node type

This trips agents up more than anything else. Pick based on *what's executing*, not habit:

| You want to... | Use |
|---|---|
| Run a pure T expression (filter, mutate, join) | `node(command = <t-expr>, runtime = T)` |
| Run R code (a model, a plot, a stats package) | `rn(...)` |
| Run Python code (ML, a specific library) | `pyn(...)` |
| Run Julia code (numerical computing, models) | `jln(...)` |
| Shell out (rsync, a CLI tool, a compiled binary) | `shn(...)` |

Every node result flows through Arrow by default (`serializer = ^arrow`) when it's tabular — don't
hand-roll CSV round-trips between languages, that's what Arrow is for.

## Worked example: adding a node to an existing pipeline

```t
p = pipeline {
  raw = node(command = read_csv("data/input.csv"), runtime = T)
  clean = raw |> filter($amount > 0) |> drop_na($amount)

  -- new node: hand off to R for a model fit
  model = rn(
    command = <{ fixest::feols(amount ~ x1 + x2, data = clean) }>,
    deps = [clean],
    serializer = ^arrow
  )
}

build_pipeline(p)
```

Notes:
- New nodes go inside the existing `pipeline { ... }` block — don't create a second pipeline.
- `deps = [clean]` makes the upstream node's Arrow output available to the R code as `clean`.
- Small, single-purpose nodes beat one big node that does read+clean+model. If a node's `command`
  is doing three things, split it.

## Debugging and inspecting a node/pipeline

1. **Check pipeline status:** Use `inspect_pipeline(p)` to view node build states, cache locations, and execution times.
2. **Examine evaluated data:** Use `read_node(p.name)` from the REPL/subshell to read and inspect the actual output of a built node.
3. **Read diagnostic logs:** `t explain --node <name>` from the shell, or `explain(read_node(p.name))` from the REPL — the `diagnostics` field tells you what actually ran and what it produced.
4. If a node errors, check `is_error()` on its output before assuming the pipeline is broken — T nodes return `Error` values rather than raising, so a "successful" run can still be carrying an error downstream until something inspects it.
5. `t doctor` catches environment drift (stale flake, missing Nix inputs) before you go chasing a phantom code bug.

## Common mistakes agents make here

- **Reassigning a variable with `=` after it's already bound.** T is immutable; use `:=` to
  rebind, or give the new value a new name. `a = 1; a = 2` is not valid T.
- **Writing a `for` loop.** There isn't one. Reach for `map()`, `summarize()`, or a colcraft verb.
- **Referencing a column as a bare name inside a colcraft verb.** `filter(df, amount > 0)` is
  wrong — it needs `filter(df, $amount > 0)`. The `$` is what makes it NSE instead of a lookup
  against the caller's environment.
- **Installing packages by hand.** No `install.packages()`, no `pip install`. Add the dependency
  to `tproject.toml` and run `t update` — that's what regenerates the Nix environment.
- **Writing to `data/`.** Treat it as read-only input. Pipeline outputs go through
  `pipeline_copy(p, node, to)` into `outputs/`.
- **Skipping the `pipeline { ... }` wrapper.** A bare script of T statements isn't runnable via
  `t run` — everything that should be cached/reproducible needs to be a node inside a pipeline.

## Before calling a task done

- `t run src/pipeline.t` (or the project's entry pipeline) completes without an unhandled `Error`.
- If you touched `tproject.toml`, you ran `t update` afterward.
- If the task involved a nontrivial analytical decision, you added an `intent { ... }` block
  documenting the assumption/goal/dependency — that's what makes the pipeline auditable later,
  by a human or another agent.
