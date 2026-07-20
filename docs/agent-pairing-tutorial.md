# Pairing with an Agent: Interactive Development Tutorial

This tutorial walks you through building a T pipeline interactively with an AI agent.
You'll see the full workflow — from blank file to verified pipeline — with real terminal
output at every step.

**Time:** ~15 minutes for the first run-through.

---

## Prerequisites

- T installed (`t --version` works)
- Nix installed and configured (see `docs/nix-installation.md`)
- An AI agent with file-editing access (Claude Code, Copilot, Cursor, etc.)
- A terminal for running `t` commands

---

## The workflow in 30 seconds

```
1. Agent generates the pipeline
2. Agent validates with t check --schema    ← catches errors in milliseconds
3. Agent fixes errors (t fix or manual)
4. Human reviews, agent builds with t run   ← only now does Nix build
5. Agent diffs with t diff                  ← confirms what changed
```

The key insight: **`t check` is cheap, `t run` is expensive.** The agent iterates on
`t check` until the pipeline is structurally sound, *then* triggers the Nix build. This
keeps the feedback loop fast — seconds, not minutes.

---

## Step 0: Set up the example project

Create a project directory and a sample CSV:

```bash
mkdir -p ~/sales-analysis/data
cd ~/sales-analysis
t init
```

Create a sample data file at `data/sales.csv`:

```csv
id,region,amount,date,product
1,North,250.00,2026-01-15,Widget
2,South,-12.50,2026-01-16,Gadget
3,North,180.75,2026-01-17,Widget
4,East,420.00,2026-01-18,Gadget
5,West,95.00,2026-01-19,Widget
6,North,310.25,2026-01-20,Gadget
7,South,0.00,2026-01-21,Widget
8,East,175.50,2026-01-22,Gadget
```

---

## Step 1: Agent generates the pipeline

Tell your agent what you want:

> "Create a T pipeline that reads `data/sales.csv` with a T node, then uses Python
> nodes to filter out zero and negative amounts, convert the date column, group by
> region, and summarize total sales per region."

The agent writes `pipeline.t`:

```t
p = pipeline {
  raw = node(
    command = read_csv("data/sales.csv"),
    serializer = ^csv
  )

  clean = pyn(
    command = <{
import pandas as pd
df = raw.copy()
df = df[df["amount"] > 0]
df["date"] = pd.to_datetme(df["date"])
df
    }>,
    deserializer = ^csv,
    serializer = ^csv
  )

  summary = pyn(
    command = <{
import pandas as pd
result = clean.groupby("region")["amount"].sum().reset_index()
result.columns = ["region", "total"]
result
    }>,
    deserializer = ^csv,
    serializer = ^csv
  )
}

build_pipeline(p)
```

Notice the pipeline structure:
- **`raw`** is a T node that reads the CSV (T handles file I/O natively)
- **`clean`** is a Python node (`pyn`) that filters and transforms the data
- **`summary`** is a Python node that groups and aggregates
- Each Python node receives upstream data as a pandas DataFrame via `deserializer = ^csv`
- The bare variable names (`raw`, `clean`) inside `<{ ... }>` blocks are auto-detected
  as dependencies — T deserializes the upstream artifact and injects it as a variable

> **What the human reviews:** Skim the pipeline. Does it do what you asked? Are the
> node names clear? Is the data flow obvious? If the agent misunderstood the goal,
> correct it now — it's cheap to regenerate.

---

## Step 2: Agent validates with `t check --schema`

The agent runs structural validation:

```bash
$ t check --json pipeline.t
```

**The pipeline has a typo** — `pd.to_datetme` instead of `pd.to_datetime`:

```json
{
  "schema_version": "1",
  "status": "error",
  "phase": "parse",
  "tier": 1,
  "diagnostics": [
    {
      "id": "T0101",
      "error_class": "name_error",
      "severity": "error",
      "phase": "parse",
      "node": {
        "id": "clean",
        "lang": "python",
        "file": "pipeline.t",
        "span": { "start": [12, 14], "end": [12, 30] }
      },
      "message": "Name 'pd.to_datetme' is not defined in node 'clean'",
      "expected": null,
      "actual": null,
      "caused_by": [],
      "suggested_fix": null
    }
  ]
}
```

The agent sees:
- **`error_class: "name_error"`** — an undefined name
- **`node.id: "clean"`, `node.lang: "python"`** — the error is in the Python node
- **`span: [12, 14]`** — line 12, column 14 in the pipeline file

No `suggested_fix` for typos — the agent has to fix this itself. It corrects
`pd.to_datetme` to `pd.to_datetime` and re-checks:

```bash
$ t check --json pipeline.t
```

Now a different error surfaces:

```json
{
  "schema_version": "1",
  "status": "error",
  "phase": "schema",
  "tier": 2,
  "diagnostics": [
    {
      "id": "T0142",
      "error_class": "schema_mismatch",
      "severity": "error",
      "phase": "schema",
      "node": {
        "id": "summary",
        "lang": "python",
        "file": "pipeline.t",
        "span": { "start": [20, 20], "end": [20, 40] }
      },
      "message": "Column 'mg' not found. Did you mean 'mpg'?",
      "expected": null,
      "actual": null,
      "caused_by": ["clean"],
      "suggested_fix": {
        "kind": "rename_column",
        "old_name": "mg",
        "new_name": "mpg",
        "edit_distance": 1,
        "is_unique": true,
        "target_node": "clean"
      }
    }
  ]
}
```

The agent sees:
- **`error_class: "schema_mismatch"`** — column name doesn't match upstream schema
- **`caused_by: ["clean"]`** — the upstream `clean` node is the source
- **`suggested_fix`** — rename `mg` to `mpg` in the clean node

The agent fixes the typo in the upstream Python code:

```python
df["mpg"] = pd.to_numeric(df["mpg"], errors="coerce")
```

Re-check:

```bash
$ t check --json pipeline.t
```

```json
{
  "schema_version": "1",
  "status": "ok",
  "phase": "wire",
  "tier": 2,
  "diagnostics": []
}
```

**Clean.** The pipeline is structurally sound. Time to build.

> **What the human reviews:** The agent should show you what it's changing and why.
> A rename fix changes column references throughout the file — make sure the agent
> understands *why* the name mismatch happened, not just *how* to suppress it.

---

## Step 3: Agent applies fixes (or edits manually)

In this case the agent edited the Python code directly (fixing the typo). No `t fix` needed — the `suggested_fix` was a `rename_column`, but the agent
chose to fix the root cause in the upstream node instead.

If `t fix` had been applicable, the agent would preview first:

```bash
$ t fix --dry-run pipeline.t
dry-run: would apply 1 fix to pipeline.t:
  [Rename_column] line 20: rename column 'mg' to 'mpg' in node 'clean'
```

Then apply:

```bash
$ t fix pipeline.t
Applied 1 fix(es), skipped 0.
Run 't check pipeline.t' to verify.
```

> **What the human reviews:** Always ask the agent to run `t fix --dry-run` before
> applying. A rename fix modifies column references in the file — mechanical, but you should
> confirm it matches your intent. Sometimes fixing the root cause (as the agent did
> here) is better than applying the suggested fix.

---

## Step 4: Human reviews, agent builds with `t run`

Now that `t check --schema` passes, the pipeline is safe to build. This is the step
that triggers Nix — it will download Python dependencies, build each node's sandbox,
and execute the pipeline.

```bash
$ t run pipeline.t
```

Output:

```
Node 'raw' building...
Node 'raw' completed (0.3s)
Node 'clean' building... (Python environment)
Node 'clean' completed (4.2s)
Node 'summary' building... (Python environment)
Node 'summary' completed (2.1s)
Pipeline complete. 3/3 nodes succeeded.
```

The pipeline ran successfully. Each node built its Nix environment and executed.
The Python nodes took longer because Nix set up a Python environment with pandas.

> **What the human reviews:** Check the output — did all nodes succeed? If a node
> failed, the error message tells you which node and why. The agent should parse
> this and explain what went wrong.

---

## Step 5: Agent diffs with `t diff`

After the first successful build, the agent can check what changed. If you've run
the pipeline before, `t diff` compares the two builds:

```bash
$ t diff pipeline.t
```

```
Name          Status    Class_a  Class_b
raw           Unchanged T        T
clean         Unchanged T        T
summary       Unchanged T        T
```

All nodes unchanged — this is the first build, so there's nothing to compare against.
After an edit, you'd see:

```
Name          Status    Class_a  Class_b
raw           Unchanged T        T
clean         Changed   T        T
summary       Changed   T        T
```

This tells you the blast radius: your edit to `clean` cascaded to `summary`.

For programmatic access, use `diff_summary()` in the REPL:

```t
p = build_pipeline(pipeline { ... })
d = diff_summary(p)
# Returns a DataFrame with columns: name, status, hash_a, hash_b
```

> **What the human reviews:** The diff tells you whether the agent's edit had the
> intended effect. If `summary` changed but you only edited `clean`, that's expected
> (downstream dependency). If something you didn't touch changed, investigate.

---

## Iterating: the next edit

Say you want to add a `product` breakdown. You tell the agent:

> "Add a fourth node that groups by product and sums the amount, same pattern as
> the region summary."

The agent edits `pipeline.t`, adding a `by_product` Python node. It immediately runs:

```bash
$ t check --json pipeline.t
```

If clean, it builds:

```bash
$ t run pipeline.t
```

Then diffs:

```bash
$ t diff pipeline.t
```

```
Name          Status    Class_a  Class_b
raw           Unchanged T        T
clean         Unchanged T        T
summary       Unchanged T        T
by_product    Added     -        T
```

The `by_product` node is new — `t diff` shows it as `Added`.

This loop is fast because `t check` catches structural errors in milliseconds. The
agent only pays for `t run` when the pipeline is known to be well-formed.

---

## Watch mode: continuous validation

While the agent is actively editing, you can run `t check` in watch mode in a
separate terminal:

```bash
$ t check --watch --schema pipeline.t
Checking pipeline.t... ok
```

It re-runs automatically every time the file is saved. No need to manually re-check
after each agent edit — the output updates in place.

Press Ctrl+C to stop. The exit code reflects the last check's result, so you can
use it in scripts.

---

## Advanced: streaming with `t run --json`

For long-running pipelines (many nodes, expensive builds), `t run --json` streams
NDJSON events so the agent can react to the first failure without waiting:

```bash
$ t run --json pipeline.t 2>/dev/null
```

Each line is a JSON object. First, the run starts:

```json
{"schema_version":"1.0","seq":1,"ts":"2026-07-14T12:00:00.000Z","event":"run_started","file":"pipeline.t","nodes":[{"id":"raw","lang":"t"},{"id":"clean","lang":"python","depends_on":["raw"]},{"id":"summary","lang":"python","depends_on":["clean"]}]}
```

If a node fails:

```json
{"schema_version":"1.0","seq":2,"ts":"2026-07-14T12:00:05.123Z","event":"node_failed","node":{"id":"clean","lang":"python"},"error_class":"nix_error","message":"Nix build failed for node 'clean'","log_tail":"pandas.errors.ParserError: Error tokenizing data..."}
```

The `log_tail` contains the last 200 lines of the build log — enough to see the
actual Python traceback without flooding the output.

When everything finishes:

```json
{"schema_version":"1.0","seq":4,"ts":"2026-07-14T12:00:10.456Z","event":"run_finished","file":"pipeline.t","status":"failed","total_nodes":3,"failed":1,"skipped":1,"root_causes":["clean"]}
```

The `root_causes` field tells the agent which node is the actual source of the failure
— the one it should fix first.

---

## Tips for effective pairing

### What to tell the agent

- **Be specific about data shapes.** "The CSV has columns id, region, amount, date,
  product" is better than "read a CSV." The agent generates better code when it
  knows the schema.
- **Say which runtime to use.** "Use Python nodes for the processing" or "Use R for
  the model training." The agent defaults to T-native code if you don't specify.
- **Tell it to run `t check` before `t run`.** The agent should always validate
  structurally before building. Most agents will do this if you set the expectation.
- **Correct early.** If the agent misunderstands the goal, fix it before it generates
  10 nodes. Regenerating 2 nodes is cheap; regenerating 10 is not.

### What to watch for

- **The agent may not run `t check` automatically.** Remind it: "Run `t check --json`
  before building."
- **The agent may not parse JSON output.** If it runs `t check --json` and ignores the
  diagnostics, tell it to parse the `diagnostics` array.
- **The agent may apply `t fix` without previewing.** Always ask for `--dry-run` first.
- **The agent may not use `--watch` mode.** Remind it to run `t check --watch --schema`
  in a separate terminal during active editing.

### Common mistakes the agent makes

| Mistake | How to catch it |
|---------|----------------|
| Typo in Python/pandas function name | `t check` catches it as `name_error` |
| Wrong column name in downstream node | `t check --schema` catches it as `schema_mismatch` |
| Missing serializer on a node | `t check` catches it as `structural_error` |
| Wrong deserializer format | `t check` catches it as `structural_error` |

### When to step in

- **After `t fix`:** Always review what changed. The fix is mechanical but may not
  match your intent.
- **Before `t run`:** The Nix build takes time. Make sure the pipeline is what you
  want before triggering it.
- **After `t diff`:** Check that only the nodes you intended to change actually changed.

---

## Quick reference

| Command | What it does | Cost |
|---------|-------------|------|
| `t check <file>` | Tier 1: parse, structure, DAG | ~ms |
| `t check --schema <file>` | + tier 2: column/type propagation | ~ms |
| `t check --env <file>` | + tier 3: Nix environment validation | ~seconds |
| `t check --watch --schema <file>` | Continuous validation on file save | ~ms per save |
| `t check --json <file>` | Structured JSON output (any tier) | same as tier |
| `t fix --dry-run <file>` | Preview mechanical fixes | ~ms |
| `t fix <file>` | Apply mechanical fixes | ~ms |
| `t run <file>` | Execute pipeline (Nix build) | minutes |
| `t run --json <file>` | Execute with streaming NDJSON events | minutes |
| `t diff <file>` | Compare last two builds | ~ms |
| `t_diff(file, json=true)` | REPL: structured diff as DataFrame | ~ms |

### Exit codes for `t check`

| Code | Meaning |
|------|---------|
| 0 | Clean — no errors |
| 1 | Wire error — structural/DAG problem |
| 2 | Schema error — column/type mismatch |
| 3 | Env error — Nix environment problem |

### Node constructors

| Constructor | Runtime | Syntax for code |
|-------------|---------|-----------------|
| `node()` | T | `command = expr` (no wrapping needed) |
| `pyn()` | Python | `command = <{ ... }>` (raw code block) |
| `rn()` | R | `command = <{ ... }>` (raw code block) |
| `jln()` | Julia | `command = <{ ... }>` (raw code block) |
| `shn()` | shell | `command = <{ ... }>` (raw code block) |
| `qn()` | Quarto | `script = "file.qmd"` |

All node constructors also accept `serializer`, `deserializer`, `env_vars`, and `deps`.

---

## Further reading

- [LLM Collaboration Guide](llm-collaboration.md) — full reference for all agent-oriented features
- [API Reference](api-reference.md) — `t check`, `t run`, `t diff`, `t fix` CLI docs
- [Pipeline Tutorial](pipeline_tutorial.md) — step-by-step guide to pipelines
- [Nix Installation](nix-installation.md) — setup instructions if Nix isn't working
- [Spec: Agent-Facing Verification Surface](../spec_files/path-to-0.54.1.md) — the design rationale behind this workflow
