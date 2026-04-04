# T Language — LLM-First Pipeline Specification

> **Status:** Draft v0.1 — for iteration  
> **Scope:** Intent blocks, agent workflow, validation protocol, and AGENTS.md standard

---

## 1. Philosophy

T is a reproducibility-first functional language for declarative data analysis. It is **not designed to be written by humans directly**. T pipelines are authored by LLMs, validated by tooling, and governed by human-written constraints. The human's role is to express goals in plain language, review machine-checkable contracts, and own the non-negotiable rules of their domain.

This document specifies:
- The **intent block** system for human-LLM collaboration
- The **AGENTS.md** standard that makes LLM behavior consistent and predictable
- The **validation loop** that enforces correctness without requiring human expertise in T syntax
- The **canonical workflow** from user goal to running pipeline

---

## 2. Intent Blocks

### 2.1 Definition

An `intent` block is a first-class construct in T, not a comment. It is attached to pipeline nodes and participates in validation, diffing, and serialization. It is the primary interface between the human and the LLM over the lifetime of a pipeline.

### 2.2 Syntax

```t
intent {
  goal:           String         -- plain language description of what this node does and why
  assumes:        List[Expr]     -- preconditions; checkable predicates on inputs
  ensures:        List[Expr]     -- postconditions; checkable predicates on outputs
  constraints:    String         -- human-written; things that MUST NOT change without explicit sign-off
  llm_hint:       String         -- LLM-facing guidance for future edits to this node
  open_questions: List[String]   -- unresolved decisions; explicit invitation for LLM or human input
  tags:           List[String]   -- optional; for filtering, coverage reports, audit
}
```

### 2.3 Field Semantics

| Field | Author | Runtime effect | Purpose |
|---|---|---|---|
| `goal` | LLM (user reviews) | None | Documents *why* this node exists |
| `assumes` | LLM | Checked on node entry | Precondition contract |
| `ensures` | LLM | Checked on node exit | Postcondition contract |
| `constraints` | **Human** | Checked by `intent_assert` | Hard rules that must survive any LLM edit |
| `llm_hint` | LLM (human edits) | None | Co-located guidance for future LLM sessions |
| `open_questions` | LLM or Human | Flagged by `t check` | Signals where judgment is still needed |
| `tags` | LLM | None | Metadata for tooling |

### 2.4 Ownership Rules

- `constraints` and `open_questions` are the **primary human interface**. The LLM drafts them; the human must review and may edit them before the pipeline is considered signed off.
- `assumes` and `ensures` are LLM-authored but **machine-enforced**. The human does not need to write them, only to trust that `t check` will catch violations.
- `llm_hint` should be written by the LLM but is explicitly addressed *to future LLMs* — a message passed forward across sessions.
- `goal` is the most human-readable field and should be comprehensible to a non-technical stakeholder.

### 2.5 Full Example

```t
p = pipeline {
  clean = node(
    command = df
      |> filter($age >= 18)
      |> filter(!is_na($spend))
      |> mutate($spend_usd = normalize_currency($spend, $currency)),

    intent = intent {
      goal: "Restrict to adult users and normalize spend to USD for downstream comparability"
      assumes: [
        ncol($in) >= 3,
        colnames($in) |> includes(["age", "spend", "currency"])
      ]
      ensures: [
        nrow($out) <= nrow($in),
        all($age >= 18),
        !any(is_na($spend_usd))
      ]
      constraints: "The age threshold of 18 is a legal requirement — do not modify without compliance sign-off. Currency normalization must produce USD."
      llm_hint: "If the input schema adds columns, preserve existing filters. If currency codes change, update normalize_currency's lookup table, not this node."
      open_questions: []
      tags: ["etl", "pii-adjacent", "legal"]
    }
  )
}
```

### 2.6 Vacuous Constraint Detection

`t check` will flag constraints that are too vague to be enforceable:

```
[WARN] node 'clean': constraint appears vague ("be careful here") — 
       consider encoding as an `ensures` predicate where possible.
       Freetext constraints are a fallback, not the default.
```

The system nudges toward machine-checkable `ensures` predicates and treats freetext `constraints` as a last resort for rules that cannot be encoded as predicates (legal requirements, business policies, compliance mandates).

---

## 3. The AGENTS.md Standard

### 3.1 Purpose

`AGENTS.md` is a **language-level artifact**, versioned with T itself, generated automatically by `t init`. It is not a user-maintained file. Its purpose is to give any LLM agent a consistent, accurate orientation to T's conventions before it touches any pipeline code.

The key design principle: **guidance must be co-located with what it governs**. `AGENTS.md` handles project-level orientation; `intent` blocks handle node-level guidance. Together they ensure that relevant context is always within the LLM's active context window when it is making edits.

### 3.2 Contents of a Generated AGENTS.md

```markdown
# AGENTS.md — T Pipeline Agent Protocol
# Auto-generated by T v{version}. Do not edit manually.

## What T Is
T is a reproducibility-first functional language. Pipelines are DAGs of nodes.
You (the LLM) write all T code. The human expresses goals in plain language
and owns `constraints` and `open_questions` fields.

## Your Responsibilities
1. Write all pipeline code in response to human goals
2. Write intent blocks for every node — no node may be left without one
3. Draft `constraints` and `llm_hint` fields; the human will review and edit them
4. Surface ambiguities as `open_questions` rather than silently choosing
5. When modifying existing nodes, read their intent block first
6. After editing a node, update its intent block to reflect the change
7. Never modify a `constraints` field without explicit human instruction
8. Always run or suggest running `t check` after making changes

## What the Human Owns
- The plain language goal they describe to you
- Review and final edit of `constraints` fields
- Resolution of `open_questions`
- The decision to run `t check` and whether to accept the result

## Intent Block Fields — Quick Reference
- `goal`: Why this node exists. Write for a non-technical reader.
- `assumes`: Checkable preconditions on input data/schema.
- `ensures`: Checkable postconditions on output. Be specific.
- `constraints`: Business/legal rules. Draft carefully; human will edit.
- `llm_hint`: Write to your future self. What should the next LLM session know?
- `open_questions`: Unresolved decisions. Don't silently pick — surface them.
- `tags`: Metadata strings for filtering and audit.

## Validation
After writing or editing any pipeline, always include this instruction to the human:
"Run `t check pipeline.t` and paste the output back to me."

## Key Language Rules
{auto-generated from T language spec: no loops, no mutable variables,
 NA errors are explicit, pipe operators, NSE with $, etc.}

## Pipeline Node Types
- `node(...)`: Native T execution
- `rn(...)`: R execution block
- `pyn(...)`: Python execution block
- `command` and `script` are mutually exclusive per node
- Use `serializer = "pmml"` for model interchange between runtimes

## Common Pitfalls
- Never leave `open_questions` non-empty at the end of a session without flagging it
- `ensures` predicates must reference columns that exist in the node's output schema
- `constraints` left empty on data-mutating nodes will fail `t check`
```

### 3.3 Session Protocol

At the start of every LLM session involving a T project, the agent should:

1. Read `AGENTS.md`
2. Read the existing `pipeline.t` if one exists
3. Note any `open_questions` fields that are non-empty — these are pending decisions
4. Proceed with the human's request

This is not enforced technically by T itself but should be specified in any T-aware coding agent's system prompt.

---

## 4. The Validation Loop

### 4.1 Design Principle

The human should never need to diagnose a T error themselves. All validation output is designed to be **pasted directly back to the LLM** for remediation. The loop is:

```
Human describes goal
  → LLM writes pipeline.t with intent blocks
    → Human runs `t check pipeline.t`
      → Output pasted to LLM
        → LLM fixes and regenerates
          → Repeat until clean
```

The human's judgment is applied to `constraints` and `open_questions`, not to syntax or logic errors.

### 4.2 `t check` Output Format

Output is structured to be LLM-parseable as well as human-readable:

```
t check pipeline.t
──────────────────────────────────────────
[PASS] pipeline structure      valid DAG, no cycles detected
[PASS] intent coverage         6/6 nodes have intent blocks
[PASS] schema consistency      all node references resolve
[FAIL] node 'score'            ensures clause references unknown column $pred_prob
                               → expected columns in output: [$user_id, $pred_label]
[FAIL] node 'clean'            constraints field is empty
                               → required for data-mutating nodes
[WARN] node 'model'            open_questions is non-empty
                               → "Should we prefer interpretability over accuracy?"
                               → human review recommended before pipeline is built
[WARN] node 'load'             assumes clause not present; node reads external data
                               → recommend adding schema assertions
──────────────────────────────────────────
2 errors, 2 warnings. Pipeline not built.
Paste this output to your LLM to resolve errors.
```

### 4.3 Validation Rules

The following rules are enforced by `pipeline_validate` / `t check`:

**Errors (block build):**
- Any node without an intent block
- Any `ensures` predicate referencing a column not present in the node's output schema
- `constraints` field empty on any node that mutates or filters data
- Cycles in the DAG
- `command` and `script` both specified on the same node

**Warnings (surfaced, do not block):**
- `open_questions` non-empty on any node
- `assumes` absent on nodes that read external data sources
- `constraints` field appears to be vague freetext with no checkable content
- `llm_hint` absent on nodes tagged as `complex` or `model`

### 4.4 Runtime Enforcement

At pipeline execution time, `assumes` and `ensures` are evaluated as live predicates:

- `assumes` runs before the node's `command` executes
- `ensures` runs after the node's `command` completes
- Failures raise a typed `IntentViolation` error that includes the node name, the failing predicate, and the actual observed value

```
IntentViolation in node 'clean'
  ensures: all($age >= 18)
  observed: 3 rows with $age < 18 in output
  → pipeline halted at node 'clean'
```

---

## 5. Canonical Workflow

### 5.1 Project Bootstrap

```bash
t init my_project
cd my_project
```

Generated structure:
```
my_project/
  AGENTS.md          ← language-level; auto-generated; do not edit
  pipeline.t         ← empty scaffold
  flake.nix          ← reproducibility environment
  .t/
    cache/           ← node execution cache
    logs/            ← per-node execution logs
```

### 5.2 First Pipeline — Human Side

The human opens a conversation with an LLM and pastes `AGENTS.md` (or the agent reads it automatically in a T-aware tool). Then:

> *"I have sales data in `data/sales.csv`. I want to clean it, remove transactions under $10, train a churn model in R, and score new customers. The $10 threshold is a business rule from finance. Keep the model swappable between R and Python."*

The LLM produces a complete `pipeline.t`. The human's only action before running `t check` is to read the `constraints` fields and decide if they accurately capture the business rules described.

### 5.3 First Pipeline — LLM Output

The LLM should produce something like:

```t
p = pipeline {

  load = node(
    command = read_csv("data/sales.csv"),
    intent = intent {
      goal: "Load raw sales data from CSV source"
      assumes: [nrow($out) > 0, colnames($out) |> includes(["transaction_id", "amount", "customer_id"])]
      ensures: [nrow($out) > 0]
      constraints: ""
      llm_hint: "If the CSV path changes, update here. If schema changes, update assumes."
      open_questions: ["Confirm expected column names with data owner before first run."]
      tags: ["io", "source"]
    }
  )

  clean = node(
    command = load
      |> filter($amount >= 10)
      |> filter(!is_na($customer_id)),
    intent = intent {
      goal: "Remove low-value and incomplete transactions"
      assumes: [colnames($in) |> includes(["amount", "customer_id"])]
      ensures: [all($amount >= 10), !any(is_na($customer_id)), nrow($out) <= nrow($in)]
      constraints: "The $10 threshold is a business rule from finance — do not modify without finance sign-off."
      llm_hint: "Preserve both filters independently. If new NA-check columns are added, append rather than replace."
      open_questions: []
      tags: ["etl", "business-rule"]
    }
  )

  model = rn(
    script = "train_churn.R",
    serializer = "pmml",
    intent = intent {
      goal: "Train a churn prediction model on cleaned sales data"
      assumes: [nrow($in) > 100]
      ensures: [type($out) == "Model"]
      constraints: "Output must be PMML-serialized to remain swappable with Python implementation."
      llm_hint: "To swap to Python, replace with pyn() pointing to train_churn.py. Keep serializer = pmml."
      open_questions: ["Should we prefer interpretability over accuracy? Logistic regression vs gradient boosting?"]
      tags: ["model", "complex"]
    }
  )

  score = node(
    command = read_csv("data/new_customers.csv")
      |> mutate($churn_prob = predict(model, $in)),
    intent = intent {
      goal: "Score new customers using trained churn model"
      assumes: [type(model) == "Model", nrow($in) > 0]
      ensures: [colnames($out) |> includes(["customer_id", "churn_prob"]), !any(is_na($churn_prob))]
      constraints: "Output must always include customer_id for join safety downstream."
      llm_hint: "If the model interface changes (e.g. different feature columns), update the mutate call here."
      open_questions: []
      tags: ["scoring", "output"]
    }
  )

}

build_pipeline(p)
```

### 5.4 Validation and Iteration

```bash
t check pipeline.t
```

Human pastes output to LLM. LLM fixes. Repeat until:

```
[PASS] all checks
Pipeline is ready to build.
```

Human reviews `open_questions` fields flagged as warnings. Resolves them with the LLM or explicitly accepts them as deferred decisions by clearing the field.

### 5.5 Change Workflow

Six months later, a new LLM session. Human says:

> *"Swap the churn model to Python/sklearn."*

The LLM reads `pipeline.t`, sees the `model` node's intent block including:

```
constraints: "Output must be PMML-serialized to remain swappable with Python implementation."
llm_hint: "To swap to Python, replace with pyn() pointing to train_churn.py. Keep serializer = pmml."
```

It makes the change correctly and updates the `goal` and `llm_hint` to reflect the new state. `t check` confirms DAG integrity and intent coverage. The constraint written months ago actively prevented the LLM from "helpfully" dropping PMML serialization.

---

## 6. Standard Library Extensions for Intent

### 6.1 New Pipeline Inspection Functions

```t
-- Returns intent blocks for all nodes as a DataFrame
pipeline_intent(p :: Pipeline) :: DataFrame

-- Returns nodes with non-empty open_questions
pipeline_open_questions(p :: Pipeline) :: DataFrame

-- Returns nodes where constraints field is empty
pipeline_unconstrained(p :: Pipeline) :: List[String]

-- Diffs intent blocks between two pipeline versions
intent_diff(p_old :: Pipeline, p_new :: Pipeline) :: DataFrame

-- Returns coverage report: which nodes have which fields populated
intent_coverage(p :: Pipeline) :: DataFrame

-- Throws if any ensures predicates fail against provided data
intent_assert(p :: Pipeline) :: Pipeline
```

### 6.2 Intent Metaprogramming

```t
-- Compose intent blocks (patch merges fields, last write wins)
base = intent { tags: ["etl"], ensures: [nrow($out) > 0] }
specific = intent { goal: "Load Q3 sales", constraints: "..." }
merged = base |> patch(specific)

-- Access intent fields programmatically
goals = pipeline_intent(p)$goal
open  = pipeline_open_questions(p)
```

---

## 7. Implementation Roadmap

### Phase 1 — Core (Required for v1)
- [ ] `intent` block parsing and AST representation
- [ ] `assumes` / `ensures` runtime evaluation at node boundaries
- [ ] `IntentViolation` error type with structured output
- [ ] `t check` command with all error and warning rules from §4.3
- [ ] `pipeline_validate` extended to cover intent rules
- [ ] `t init` generating `AGENTS.md` from language version

### Phase 2 — Tooling
- [ ] `pipeline_intent()` function
- [ ] `intent_diff()` for pipeline version comparison
- [ ] `intent_coverage()` report
- [ ] `pipeline_open_questions()` filter
- [ ] Vacuous constraint detection heuristic

### Phase 3 — Agent Integration
- [ ] Official T language server plugin that surfaces intent fields in editor on hover
- [ ] `t check` output schema documented for LLM consumption
- [ ] Reference system prompt fragment for T-aware coding agents
- [ ] CI integration: `t check --strict` as a pipeline gate

---

## 8. Open Questions

These are unresolved design decisions for the next iteration:

1. **Assumes/ensures language**: Should predicates be T expressions (as specified here) or a constrained sublanguage? Full T expressions are powerful but could allow side effects in contracts.

2. **Constraint enforcement**: `constraints` is currently freetext only. Should there be a way to link a freetext constraint to a corresponding `ensures` predicate, so the system can verify they are consistent?

3. **LLM hint staleness**: `llm_hint` can become stale after edits. Should `t check` warn when a node was modified but its `llm_hint` was not touched in the same commit?

4. **AGENTS.md extensibility**: Should users be able to append project-specific sections to `AGENTS.md` without losing auto-generated content on the next `t init`? Proposal: a `## Project Notes` section that is preserved across regenerations.

5. **Intent block inheritance**: Should pipeline-level intent be expressible, with node-level intent inheriting and overriding? Useful for tagging an entire pipeline with a compliance context.

---

*End of T_SPEC.md v0.1*
