# Implementation Plan — `t explain`

This document describes a concrete, engineering-facing plan to implement **`t explain`**, one of the core tooling primitives of the T programming language.

`t explain` is not a debugging aid bolted on after the fact. It is a **first-class introspection interface** designed to support human reasoning, reproducibility, and LLM-assisted workflows.

The plan is structured in phases so it can be implemented incrementally, starting in alpha and deepened through beta.

---

## Purpose of `t explain`

`t explain` produces a **machine-readable and human-readable explanation** of a value, expression, or pipeline node.

It answers questions such as:

* What is this value?
* Where did it come from?
* What assumptions apply to it?
* What can go wrong downstream?
* What context should an LLM see to modify this safely?

`t explain` is designed to be:

* Deterministic
* Side-effect free
* Stable across runs
* Serializable

---

## Core Design Principles

1. **Everything explainable must be explicit**
   If a property cannot be explained, it should not exist implicitly in the runtime.

2. **Structured first, pretty second**
   The primary output is structured data; formatting is a view.

3. **Locality over completeness**
   `t explain` explains *this thing*, not the entire program.

4. **Forward-compatible**
   The schema must evolve without breaking tooling.

---

## What `t explain` Can Target

Initial supported targets:

* Runtime values
* DataFrames
* Pipeline nodes

Later extensions:

* Expressions
* Functions
* Models (e.g. `lm` results)

---

## Output Model (Core Schema)

`t explain` returns a structured object with the following top-level fields:

```t
Explain {
  kind: "dataframe" | "value" | "pipeline_node",
  summary: {...},
  schema: {...},
  stats: {...},
  provenance: {...},
  invariants: [...],
  errors: [...],
  downstream: [...]
}
```

All fields are optional except `kind` and `summary`.

---

## Phase 1 — Minimal Explain (Alpha)

**Goal**: Make `t explain` useful and trustworthy early.

### Supported Targets

* Scalars
* Vectors
* DataFrames
* Pipeline nodes (shallow)

### Implement

#### 1. Explainable Runtime Metadata

Extend runtime values with optional metadata:

* Type
* Origin (source expression or node)
* Creation timestamp (logical, not wall-clock)

This metadata must be:

* Immutable
* Cheap to copy
* Optional

---

#### 2. DataFrame Explanation

For DataFrames, collect:

* Column names and types
* Row count
* NA counts per column
* Example rows (configurable, e.g. first 5)

No lineage or history yet.

---

#### 3. Pipeline Node Explanation

For a pipeline node:

* Node name
* Dependencies
* Output kind
* Cached or recomputed

---

#### 4. CLI Interface

```sh
t explain <expr | node>
```

Default output:

* Pretty-printed, stable text
* Deterministic ordering

Optional flag:

```sh
t explain --json <target>
```

### Acceptance Criteria

* `t explain` never crashes
* Output is deterministic
* JSON output round-trips cleanly

---

## Phase 2 — Semantic Context (Late Alpha / Early Beta)

**Goal**: Explain meaning, not just shape.

### Implement

#### 1. Provenance Tracking

Attach lightweight provenance to explainable values:

* Source pipeline node
* Transform name (`select`, `mutate`, etc.)
* Parent columns (if applicable)

This must remain *approximate*, not a full lineage graph.

---

#### 2. Invariants and Assertions

Expose:

* Active `assert()` statements
* Group-level invariants
* Whether invariants have been checked

---

#### 3. Error Surface

Include:

* Possible error codes
* Conditions under which they arise
* Whether errors have occurred already

---

### Acceptance Criteria

* Users can answer “why did this value look like this?”
* LLMs can infer safe modification boundaries

---

## Phase 3 — Pipeline Awareness (Beta)

**Goal**: Make pipelines explainable as systems.

### Implement

#### 1. Downstream Awareness

For a pipeline node, include:

* Which nodes depend on it
* How changes would propagate

---

#### 2. Logical Plan Summary

Expose a simplified logical plan:

* Operators
* Evaluation order
* Materialization points

No performance claims yet.

---

#### 3. Grouped DataFrame Explain

For grouped objects:

* Group keys
* Group counts
* Group-level NA and error stats

---

### Acceptance Criteria

* Users can predict the impact of changes
* Tooling can select minimal regeneration scopes

---

## Phase 4 — LLM-Ready Exports (Beta)

**Goal**: Make `t explain` a stable prompt interface.

### Implement

#### 1. Prompt-Oriented Views

Add output modes:

* `--compact`
* `--llm`

These:

* Remove noise
* Preserve semantics
* Use stable phrasing

---

#### 2. Intent Block Integration

If present, include:

* Nearest intent block
* Associated assumptions
* Associated checks

---

### Acceptance Criteria

* `t explain --llm` can be embedded directly into prompts
* Output changes are versioned and documented

---

## Phase 5 — Stabilization and Guarantees

**Goal**: Make `t explain` dependable infrastructure.

### Implement

* Schema versioning
* Backward compatibility guarantees
* Golden tests for output

---

## Non-Goals

`t explain` will NOT:

* Execute code
* Infer intent
* Optimize pipelines
* Replace documentation

---

## Success Criteria

`t explain` is successful when:

* Users trust it more than comments
* Engineers rely on it for debugging
* LLM workflows depend on it as a primary context source
* Breaking it is treated as a serious regression

---

## Final Note

`t explain` is the foundation upon which safe automation, reproducibility, and collaboration are built. Its implementation should favor **clarity, stability, and explicitness** over cleverness or completeness.
