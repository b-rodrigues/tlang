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

> "Create a T pipeline that reads `data/sales.csv`, filters out zero and negative
> amounts, converts the date column, groups by region, and summarizes total sales
> per region. Add an expect() contract on the final output."

The agent writes `pipeline.t`:

```t
df = read_csv("data/sales.csv")

clean = df |>
  filter($amount > 0) |>
  mutate($date = as.Date($date)) |>
  expect(columns = ["id", "region", "amount", "date", "product"])

summary = clean |>
  group_by($region) |>
  summarize(total = sum($amount)) |>
  expect(columns = ["region", "total"])
```

> **What the human reviews:** Skim the pipeline. Does it do what you asked? Are the
> node names clear? Is the data flow obvious? If the agent misunderstood the goal,
> correct it now — it's cheap to regenerate.

---

## Step 2: Agent validates with `t check --schema`

The agent runs structural validation:

```bash
$ t check --schema pipeline.t
```

**If the pipeline has errors**, the agent gets structured JSON it can parse and fix:

```json
{
  "schema_version": "1",
  "status": "error",
  "phase": "schema",
  "tier": 2,
  "diagnostics": [
    {
      "id": "T0142",
      "error_class": "name_error",
      "severity": "error",
      "phase": "schema",
      "node": {
        "id": "clean",
        "lang": "t",
        "file": "pipeline.t",
        "span": { "start": [6, 14], "end": [6, 25] }
      },
      "message": "Function 'as.Date' is not defined. Did you mean 'as_date'?",
      "expected": null,
      "actual": null,
      "caused_by": [],
      "suggested_fix": {
        "kind": "rename_column",
        "old_name": "as.Date",
        "new_name": "as_date",
        "target_node": "clean"
      }
    }
  ]
}
```

The agent sees:
- **`error_class: "name_error"`** — a function doesn't exist
- **`node.id: "clean"`** — the error is in the `clean` node
- **`span: [6, 14]`** — line 6, column 14
- **`suggested_fix`** — rename `as.Date` to `as_date`

The agent fixes it and re-checks:

```bash
$ t check --schema pipeline.t
```

Now it hits the next issue:

```json
{
  "schema_version": "1",
  "status": "error",
  "phase": "schema",
  "tier": 2,
  "diagnostics": [
    {
      "id": "T0201",
      "error_class": "na_predicate_error",
      "severity": "warning",
      "phase": "schema",
      "node": {
        "id": "summary",
        "lang": "t",
        "file": "pipeline.t",
        "span": { "start": [12, 22], "end": [12, 36] }
      },
      "message": "Function 'sum' in node 'summary' may propagate NA values. Consider adding na_rm = true.",
      "expected": null,
      "actual": null,
      "caused_by": ["clean"],
      "suggested_fix": {
        "kind": "add_node_arg",
        "node": "summary",
        "arg": "na_rm = true",
        "target_node": "summary"
      }
    }
  ]
  ]
}
```

The agent sees:
- **`error_class: "na_predicate_error"`** — NA propagation risk
- **`caused_by: ["clean"]`** — the upstream `clean` node might produce NAs
- **`suggested_fix`** — add `na_rm = true` to the `sum()` call

The agent can apply this fix automatically with `t fix`, or edit manually.

> **What the human reviews:** The agent should show you what it's changing and why.
> Check that the fixes make sense — a `rename_column` fix is usually safe, but
> `add_node_arg` changes the function's behavior (NA handling). Make sure the agent
> explains what `na_rm = true` does.

---

## Step 3: Agent applies fixes with `t fix`

The agent can preview fixes before applying:

```bash
$ t fix --dry-run pipeline.t
dry-run: would apply 1 fix to pipeline.t:
  [Add_node_arg] line 12: add na_rm = true to summary
```

If it looks right, apply:

```bash
$ t fix pipeline.t
Applied 1 fix(es), skipped 0.
Run 't check pipeline.t' to verify.
```

Re-validate:

```bash
$ t check --schema pipeline.t
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

> **What the human reviews:** Run `git diff` to see what `t fix` changed. The fix
> is mechanical — it inserted a comma-separated argument — but you should confirm
> the agent's intent matches the change.

---

## Step 4: Human reviews, agent builds with `t run`

Now that `t check --schema` passes, the pipeline is safe to build. This is the step
that triggers Nix — it will download dependencies, build each node's environment, and
execute the pipeline.

```bash
$ t run pipeline.t
```

Output:

```
Node 'df' building...
Node 'df' completed (0.3s)
Node 'clean' building...
Node 'clean' completed (1.2s)
Node 'summary' building...
Node 'summary' completed (0.8s)
Pipeline complete. 3/3 nodes succeeded.
```

The pipeline ran successfully. Each node built its Nix environment and executed.

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
df            Unchanged T        T
clean         Unchanged T        T
summary       Unchanged T        T
```

All nodes unchanged — this is the first build, so there's nothing to compare against.
After an edit, you'd see:

```
Name          Status    Class_a  Class_b
df            Unchanged T        T
clean         Changed   T        T
summary       Changed   T        T
```

This tells you the blast radius: your edit to `clean` cascaded to `summary`.

For programmatic access, use `diff_summary()` in the REPL:

```t
p = pipeline { ... }
d = diff_summary(p)
# Returns a DataFrame with columns: name, status, hash_a, hash_b
```

> **What the human reviews:** The diff tells you whether the agent's edit had the
> intended effect. If `summary` changed but you only edited `clean`, that's expected
> (downstream dependency). If something you didn't touch changed, investigate.

---

## Iterating: the next edit

Say you want to add a `product` breakdown. You tell the agent:

> "Add a second summary grouped by product instead of region."

The agent edits `pipeline.t`, then immediately runs:

```bash
$ t check --schema pipeline.t
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
df            Unchanged T        T
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

Each line is a JSON object:

```json
{"schema_version":"1.0","seq":1,"ts":"2026-07-14T12:00:00.000Z","event":"run_started","file":"pipeline.t","nodes":[{"id":"df","lang":"t"},{"id":"clean","lang":"t","depends_on":["df"]},{"id":"summary","lang":"t","depends_on":["clean"]}]}
```

If a node fails:

```json
{"schema_version":"1.0","seq":2,"ts":"2026-07-14T12:00:05.123Z","event":"node_failed","node":{"id":"clean","lang":"t"},"error_class":"runtime_error","message":"Column 'date' not found","log_tail":"...last 200 lines of build log..."}
```

The agent can parse this and react immediately — no need to wait for the full build.

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
- **Ask for `expect()` contracts.** Agents won't add them by default. Tell it:
  "Add an expect() on the final output with columns X, Y, Z." This catches schema
  drift on future edits.
- **Tell it to run `t check` before `t run`.** The agent should always validate
  structurally before building. Most agents will do this if you set the expectation.
- **Correct early.** If the agent misunderstands the goal, fix it before it generates
  10 nodes. Regenerating 2 nodes is cheap; regenerating 10 is not.

### What to watch for

- **The agent may not run `t check` automatically.** Remind it: "Run `t check --schema`
  before building."
- **The agent may not parse JSON output.** If it runs `t check --json` and ignores the
  diagnostics, tell it to parse the `diagnostics` array.
- **The agent may apply `t fix` without previewing.** Always ask for `--dry-run` first.
- **The agent may not use `--watch` mode.** Remind it to run `t check --watch --schema`
  in a separate terminal during active editing.

### Common mistakes the agent makes

| Mistake | How to catch it |
|---------|----------------|
| Uses a function that doesn't exist | `t check` catches it as `name_error` |
| Missing `na_rm` on aggregate functions | `t check --schema` warns with `na_predicate_error` |
| Wrong column name | `t check --schema` catches it as `schema_mismatch` |
| Broken pipe chain | `t check` catches it as `structural_error` |
| Forgets `expect()` contracts | Run `t check --schema` — it validates contracts |

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

---

## Further reading

- [LLM Collaboration Guide](llm-collaboration.md) — full reference for all agent-oriented features
- [API Reference](api-reference.md) — `t check`, `t run`, `t diff`, `t fix` CLI docs
- [Nix Installation](nix-installation.md) — setup instructions if Nix isn't working
- [Spec: Agent-Facing Verification Surface](../spec_files/path-to-0.54.1.md) — the design rationale behind this workflow
