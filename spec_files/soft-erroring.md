# Soft-Erroring and Cross-Node Recovery

This document specifies the transition from "Fail-Fast DAGs" to "Resilient DAGs" in T-Lang.

## 1. Problem Statement
Currently, the pipeline evaluator (`eval_pipeline` and `rerun_pipeline` in `eval.ml`) implements an aggressive short-circuiting mechanism: if any dependency of a node evaluates to a `VError`, the dependent node is immediately marked as a `VError` with an "Upstream error" prefix.

This prevents the use of the Maybe-Pipe (`?|>`) and `is_error()` checks across node boundaries, effectively breaking the "Errors are Values" principle at the pipeline scale.

## 2. Specification: Resilient DAG Evaluation

### 2.1. Removal of DAG-Level Short-Circuit
The evaluator must **no longer** pre-emptively check for `VError` in a node's dependencies during the topological fold. Instead:
- Every node's `command` must be allowed to execute via `eval_expr`.
- It is the responsibility of the `command` expression to decide how to handle incoming errors.
- Standard pipes (`|>`) and standard functions will naturally propagate errors (preserving existing fail-fast behavior for unhandled errors).
- Recovery operators (`?|>`, `match`, `is_error()`) will now correctly receive the `VError` value from upstream nodes.

### 2.2. Enhanced Diagnostics
To maintain auditability, nodes must track their relationship with upstream failures even if they recover.

#### `node_diagnostics` Extension
The `node_diagnostics` structure (in `ast.ml`) will be extended:
```ocaml
and node_diagnostics = {
  nd_warnings : node_warning list;
  nd_error : node_error option;
  nd_warnings_suppressed : bool;
  nd_recovered : bool;                 (* NEW: True if node produced non-error from error input *)
  nd_upstream_errors : string list;    (* NEW: Names of failed dependencies *)
}
```

#### `build_node_diagnostics` Logic
When computing diagnostics for node `N`:
1.  Identify all dependencies `D` that evaluate to `VError`.
2.  Set `nd_upstream_errors` to the names of those dependencies.
3.  If `nd_upstream_errors` is NOT empty AND the resulting value of `N` is NOT a `VError`, set `nd_recovered = true`.

## 3. Summarization and Presentation

### 3.1. CLI Summary Updates
The `print_pipeline_diagnostics_summary` function will be updated to include a third category of results:

| Status | Symbol | Meaning |
| :--- | :---: | :--- |
| **Success** | `✔` | Produced a value; no upstream errors. |
| **Recovered**| `❍` | Produced a value despite upstream errors. |
| **Error** | `✖` | Produced a `VError`. |

**Example Output:**
```text
Pipeline summary: 0 node(s) with warnings, 1 error(s), 2 recovered
  ✖  raw_data — File 'data.csv' not found.
  ❍  clean_data — Recovered from upstream error in `raw_data`.
  ❍  summary_stats — Recovered from upstream error in `raw_data`.
```

### 3.2. Pipeline Audit Log
The `read_node()` and `explain()` functions must surface `recovered` status and point back to the original causal error, ensuring that "Soft-Erroring" does not accidentally hide the fact that a failure occurred upstream.

## 4. Implementation Goals
1.  **Modify `ast.ml`**: Update `node_diagnostics` and related unparsers.
2.  **Modify `eval.ml`**: 
    - Remove the `upstream_err_opt` check in `eval_pipeline` and `rerun_pipeline`.
    - Update `build_node_diagnostics` to populate recovery flags.
    - Update `print_pipeline_diagnostics_summary` for the new symbols.
