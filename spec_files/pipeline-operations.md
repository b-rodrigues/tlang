# T Language — Pipeline Operations Implementation Plan
*Engineering Roadmap | Draft 1.0*

---

## Overview

This document defines the phased implementation plan for first-class Pipeline manipulation in the T language. The goal is to extend the existing `colcraft` vocabulary to operate on Pipelines as data structures — enabling filtering, mutation, set operations, DAG-aware transformations, and inspection, with a consistent naming convention and lazy validation semantics.

The implementation is divided into four phases, each building on the last:

- **Phase 1** establishes the internal data model for Pipelines as inspectable, manipulable objects.
- **Phase 2** implements node-level operations (the `_node` suffix family).
- **Phase 3** implements set operations and DAG-aware transformations.
- **Phase 4** implements composition, inspection utilities, and developer tooling.

---

## Design Principles

- **Naming convention**: Operations on nodes within a pipeline take the `_node` suffix (`filter_node`, `mutate_node`). Operations on the pipeline as a whole do not (`union`, `difference`, `upstream_of`).
- **Immutability**: All pipeline operations return new `Pipeline` values. No in-place mutation.
- **Lazy validation**: DAG validity is not checked at operation time. Errors surface only at `build_pipeline()` or `pipeline_run()`.
- **Name collisions**: Hard errors on collision in `union` and similar ops. It is the user's responsibility to resolve via `rename_node`.
- **`swap()` contract**: The new node must carry the same name as the target. Mismatch is an immediate error. This is intentional — explicitness prevents swapping wrong nodes.

---

## Phase 1 — Pipeline Internal Data Model

> Prerequisite infrastructure — expose Pipeline as a queryable structure

Before any manipulation functions can be implemented, the Pipeline type must be refactored to expose its internal node graph as an inspectable, structured object. This phase has no user-facing API but is the foundation for all subsequent phases.

### 1.1 Node Metadata Schema

Each node in a pipeline must carry a well-defined metadata record with the following fields:

| Field | Type | Description |
|---|---|---|
| `name` | `String` | Unique identifier within the pipeline |
| `runtime` | `String` | One of `"T"`, `"R"`, `"python"` |
| `serializer` | `String` | e.g. `"pmml"`, `"default"` |
| `deserializer` | `String` | |
| `noop` | `Bool` | |
| `deps` | `List[String]` | Names of nodes this node depends on |
| `depth` | `Int` | Topological depth in the DAG (computed, not stored) |
| `command_type` | `String` | `"expr"` or `"script"` |

### 1.2 Pipeline as Graph

Internally, a Pipeline must be representable as an adjacency list (or equivalent) over named nodes. The build step must be separated from the graph representation, so that the graph can be traversed, queried, and transformed independently.

### 1.3 `pipeline_to_frame()`

Implement a low-level function that converts a Pipeline to a DataFrame of node metadata. This will be used internally by `select_node` and `pipeline_summary`, and is a useful debugging primitive on its own.

```t
pipeline_to_frame(p)  -- returns DataFrame with one row per node
```

### Phase 1 Deliverables

| Deliverable | Description | Owner |
|---|---|---|
| Node metadata schema | Define and implement the full metadata struct per node | Core/Runtime |
| Graph representation | Refactor Pipeline internals to adjacency list model | Core/Runtime |
| Depth computation | Topological sort to derive `$depth` per node at query time | Core/Runtime |
| `pipeline_to_frame()` | Internal + exposed utility: Pipeline → DataFrame | Stdlib |

---

## Phase 2 — Node-Level Operations (`_node` family)

> `filter`, `mutate`, `rename`, `select`, `arrange` on pipeline nodes

This phase implements the colcraft-style verbs that operate on individual nodes within a pipeline. These mirror the DataFrame API as closely as possible, with NSE (`$field`) for node metadata fields.

### 2.1 `filter_node`

Returns a new pipeline containing only nodes where the predicate is true. No DAG validity check — if a retained node depends on a removed node, that is the user's problem.

```t
p |> filter_node($runtime == "python")
p |> filter_node($noop == false)
p |> filter_node($depth <= 2)
```

### 2.2 `mutate_node`

Modifies metadata fields on matching nodes. Supports a `.where` clause to scope changes. Without `.where`, all nodes are affected.

```t
p |> mutate_node($noop = true)
p |> mutate_node($serializer = "pmml", .where = $runtime == "R")
```

### 2.3 `rename_node`

Renames a single node by name. Also rewires all edges referencing the old name. This is the canonical escape hatch for resolving name collisions before set operations.

```t
p |> rename_node("model_r", "model_r_v2")
```

### 2.4 `select_node`

Returns a DataFrame (not a pipeline) summarising node metadata. This is a read/inspection operation, not a structural transformation.

```t
p |> select_node($name, $runtime, $deps)
```

### 2.5 `arrange_node`

Returns a new pipeline with nodes sorted by a metadata field. This affects printing/serialization order only — execution order is always determined by the DAG.

```t
p |> arrange_node($depth)
p |> arrange_node($runtime)
```

### Phase 2 Deliverables

| Deliverable | Description | Owner |
|---|---|---|
| `filter_node()` | Predicate filtering over node metadata with NSE | Stdlib |
| `mutate_node()` | Field mutation with optional `.where` scoping | Stdlib |
| `rename_node()` | Rename node + rewire all dependent edges | Stdlib |
| `select_node()` | Metadata projection → DataFrame (read-only) | Stdlib |
| `arrange_node()` | Sort nodes for display; no effect on execution | Stdlib |
| NSE for node fields | Extend `$` prefix NSE to Pipeline node metadata | Parser/Eval |
| Test suite | Unit tests for each op, including invalid DAG cases | QA |

---

## Phase 3 — Set Operations & DAG-Aware Transformations

> `union`, `difference`, `intersect`, `patch`, `swap`, `rewire`, `prune`, subgraph extraction

This phase implements operations that treat pipelines as sets of named nodes, and operations that are structurally aware of the DAG. These are the most powerful operations in the system and require careful error messaging.

### 3.1 Set Operations

#### `union`

```t
p1 |> union(p2)
```

Merges two pipelines. Errors immediately on any name collision. It is the user's responsibility to `rename_node` before calling `union`.

#### `difference`

```t
p1 |> difference(p2)
```

Removes from `p1` all nodes whose names appear in `p2`. No DAG check. Nodes in `p2` that are not in `p1` are silently ignored.

#### `intersect`

```t
p1 |> intersect(p2)
```

Retains only nodes present by name in both pipelines, taking definitions from `p1`.

#### `patch`

```t
p1 |> patch(p2)
```

Like `union`, but only updates nodes that already exist in `p1` — will not add new nodes from `p2`. Useful for overriding node configurations without accidentally importing stray nodes.

### 3.2 DAG-Aware Operations

#### `swap`

```t
new_model = rn(name = "model_r", command = <{ ... }>, serializer = "pmml")
p |> swap(new_model)
```

Replaces a node's implementation. The new node must carry the exact same name as the node being replaced — this is enforced as a hard error. Edges are preserved. The name is read directly off the new node; no target name argument is required.

#### `rewire`

```t
p |> rewire("model_py", replace = list(data = "data_v2"))
```

Reroutes a node's dependencies. The `replace` argument is a named list mapping old dependency names to new ones.

#### `prune`

```t
p |> prune()
```

Removes all leaf nodes that have no downstream dependents. Useful for cleaning up intermediate pipelines after `filter_node` or `difference` operations.

#### `upstream_of` / `downstream_of` / `subgraph`

```t
p |> upstream_of("predictions")   -- node + all ancestors
p |> downstream_of("data")        -- node + all descendants
p |> subgraph("model_r")          -- full connected component
```

All three return new Pipelines, not DataFrames. These are the primary tools for extracting meaningful sub-pipelines.

### Phase 3 Deliverables

| Deliverable | Description | Owner |
|---|---|---|
| `union()` | Merge pipelines; hard error on name collision | Stdlib |
| `difference()` | Remove nodes by name from p2 | Stdlib |
| `intersect()` | Keep only shared names, p1 definitions win | Stdlib |
| `patch()` | Override existing nodes only, no additions | Stdlib |
| `swap()` | Replace node impl; enforce name match; preserve edges | Stdlib |
| `rewire()` | Reroute named dependencies of a node | Stdlib |
| `prune()` | Remove childless leaf nodes | Stdlib |
| `upstream_of()` | Extract node + all ancestors | Stdlib |
| `downstream_of()` | Extract node + all descendants | Stdlib |
| `subgraph()` | Full connected component extraction | Stdlib |
| Error messages | Helpful errors for swap mismatch, collision, missing nodes | Stdlib/Runtime |
| Test suite | Set ops with collision cases; DAG traversal correctness | QA |

---

## Phase 4 — Composition, Inspection & Tooling

> `chain`, `parallel`, inspection API, validation utilities, DOT export

This final phase completes the surface area with higher-level composition operators, a full inspection API, and developer tooling to support debugging and visualization of pipelines.

### 4.1 Composition

#### `chain`

```t
p_etl |> chain(p_model)
```

Connects two pipelines by automatically wiring outputs of `p_etl` to inputs of `p_model` where names match. Errors if no matching edges can be found, or if the wiring would be ambiguous.

#### `parallel`

```t
parallel(p_r_model, p_py_model)
```

Combines two pipelines that are intended to run independently. Errors on name collision. Outputs are not automatically wired — that is left to the user or a subsequent merge step.

### 4.2 Inspection API

```t
pipeline_nodes(p)    :: List[String]          -- names of all nodes
pipeline_edges(p)    :: List[(String, String)] -- dependency pairs (from, to)
pipeline_roots(p)    :: List[String]          -- nodes with no dependencies
pipeline_leaves(p)   :: List[String]          -- nodes with no dependents
pipeline_depth(p)    :: Int                   -- maximum topological depth
pipeline_cycles(p)   :: List                  -- should always be empty; useful for validation
pipeline_summary(p)  :: DataFrame             -- full metadata frame, wraps pipeline_to_frame()
```

### 4.3 Validation Utilities

Although validation is lazy by design, users should be able to validate explicitly when they want to:

```t
pipeline_validate(p) :: List[Error]   -- returns all validation errors, does not throw
pipeline_assert(p)   :: Pipeline      -- throws on first error, returns p on success
```

This gives users an opt-in strict mode without breaking the lazy-by-default contract.

### 4.4 Developer Tooling

- `pipeline_print(p)` — pretty-print node list with runtime, depth, noop status
- `pipeline_dot(p)` — export pipeline as a DOT graph string for Graphviz visualization
- Error message quality pass — review all Phase 2 and 3 errors for clarity and actionability
- Documentation — docstrings and examples for every new function

### Phase 4 Deliverables

| Deliverable | Description | Owner |
|---|---|---|
| `chain()` | Auto-wire two pipelines on matching names | Stdlib |
| `parallel()` | Combine independent pipelines; collision = error | Stdlib |
| `pipeline_nodes/edges/roots/leaves/depth/cycles()` | Full inspection surface | Stdlib |
| `pipeline_summary()` | DataFrame view of full pipeline metadata | Stdlib |
| `pipeline_validate()` / `pipeline_assert()` | Opt-in eager validation | Stdlib/Runtime |
| `pipeline_print()` | Human-readable node summary | Stdlib |
| `pipeline_dot()` | DOT graph export for visualization | Stdlib |
| Docs + docstrings | Complete API documentation for all new functions | Docs |
| End-to-end test suite | Full integration tests across all 4 phases | QA |

---

## Summary

| Phase | Name | Key Deliverables | Dependencies |
|---|---|---|---|
| 1 | Data Model | Node metadata schema, graph representation, `pipeline_to_frame()` | None |
| 2 | `_node` Operations | `filter_node`, `mutate_node`, `rename_node`, `select_node`, `arrange_node` | Phase 1 |
| 3 | Set & DAG Ops | `union`, `difference`, `intersect`, `patch`, `swap`, `rewire`, `prune`, subgraph | Phases 1–2 |
| 4 | Composition & Tooling | `chain`, `parallel`, inspection API, validation, DOT export | Phases 1–3 |
