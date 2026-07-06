# Review: src/eval.ml

**Lines**: 3764
**Severity summary**: 2 critical, 6 warning, 3 info

---

## CRITICAL: Use of `List.hd` (partial function on possibly-empty lists)

- **Line 1998**: `List.hd offenders` — `offenders` is checked non-empty on line 1997, so it is safe, but `List.hd` is a partial function that raises `Failure "hd"` on empty lists. Should use pattern matching instead.

  ```ocaml
  let offender = List.hd offenders in
  ```

  **Fix**: Replace with `match offenders with offender :: _ -> ... | [] -> ...` (or use `List.find` if only the first is needed).

- **Line 2006**: `List.hd validation_errors` — same issue, guarded by non-empty check but still uses a partial function.

  ```ocaml
  Error.make_error StructuralError (List.hd validation_errors)
  ```

  **Fix**: Use pattern matching: `match validation_errors with [msg] | msg :: _ -> ... | [] -> ...`.

---

## CRITICAL: Unvalidated `List.nth` access

- **Line 2538**: `List.nth items index` — guarded by `index >= 0 && index < List.length items` on lines 2537-2538, so correct at runtime. However, `List.nth` raises `Failure "nth"` on empty/short lists. Prefer `List.nth_opt` and handle `None`.

  ```ocaml
  if index >= 0 && index < List.length items then snd (List.nth items index)
  ```

  **Fix**: Use `match List.nth_opt items index with Some item -> snd item | None -> VNA NAGeneric`.

---

## WARNING: `eval_expr` function too long (~580 lines, lines 996-1575)

The main evaluation dispatch function handles all expression types, the call/pipeline construction logic, and is extremely long. The node/pipeline construction section (lines 1100-1556) alone is ~456 lines of deeply nested logic. Consider extracting:

- The node-construction path (`node`/`pyn`/`rn`/`jln`/`qn`/`shn` at line 1099) into a separate `eval_node_construction` function.
- The pipeline argument lookups (`lookup_env_vars`, `lookup_runtime_args`, `lookup_dependencies`, `lookup_pattern`, `lookup_iteration`) could each be standalone functions.

---

## WARNING: `eval_pipeline` function too long (~360 lines, lines 1726-2086)

Contains desugaring, topological sort, noop propagation, cross-runtime validation, and pipeline result construction. Consider extracting:

- `desugar_node` (lines 1847-1888) is already an inner function — good, but still within `eval_pipeline`.
- `compute_deps` (lines 1916-1956) could be extracted.
- Noop propagation (lines 1962-1980) could be a separate function.
- Cross-runtime validation (lines 1982-2006).

---

## WARNING: `eval_call` function too long (~355 lines, lines 3059-3414)

Contains NSE argument transformation, spliced argument processing, lambda application, built-in dispatch, and symbol resolution. `process_args_spliced` (lines 3190-3233) and `apply_lambda` (lines 3271-3336) are inner functions that further increase complexity.

---

## WARNING: `eval_dot_access_val` deeply nested match/conditional (lines 2781-2971, ~190 lines)

The VDict branch (lines 2796-2849) has up to 6 levels of nested match/if expressions, making the control flow hard to follow. Consider extracting the partial dot-access logic (lines 2800-2849) into separate helper functions.

---

## WARNING: Excessive use of catch-all `with _ ->` in evaluation contexts

- **Line 2500**: `with _ -> None` in `eval_dep_len` — catches all exceptions including coding errors (e.g., pattern match failures). Used in an optional/best-effort context (branch length computation), but broad catching can hide real bugs.

  ```ocaml
  match eval_expr (ref env) expr with
  | Ast.VList items -> Some (List.length items)
  | ...
  with _ -> None
  ```

- **Line 2549**: Same pattern in `eval_dep_at_index`.

- **Line 2637**: Same pattern in `pattern_branch_names_for_error`.

  **Fix**: List specific exceptions (e.g., `with | Error _ -> None`) or validate inputs before calling `eval_expr`.

---

## WARNING: Global mutable module state

- **Line 205**: `let show_warnings = ref true` — global mutable flag.
- **Line 207-209**: `let global_warnings : Ast.node_warning list ref = ref []` — global mutable accumulator.
- **Line 216**: `let current_node_warning_emitter` — global mutable emitter.
- **Line 220-224**: Multiple global refs (`last_node_diagnostics`, `last_pipeline_exprs`, `last_evaluated_node_name`, `current_node_suppression_requested`).
- **Line 228**: `pipeline_construction_mode` — global mutable flag.
- **Line 849**: `current_imports` — global mutable accumulator.

While some of these are necessary for the current architecture (warning emitter, pipeline construction flag), many could be threaded through function parameters or encapsulated in a record.

---

## INFO: Use of `List.nth` with validated bounds (lines 1730-1731)

- **Lines 1730-1731**: `List.nth parts (List.length parts - 2)` and `List.nth parts (List.length parts - 1)` are guarded by `List.length parts >= 3` but still use a partial function. Prefer `List.nth_opt` even when bounds are validated.

---

## INFO: Consider extracting `strip_dollar_prefix` to a utility module

- **Lines 267-273**: `strip_dollar_prefix` is also defined in `src/packages/pipeline/pipeline_dag_ops.ml` and possibly elsewhere. Consider a shared utility to avoid duplication.

---

## INFO: `try_lazy_expand_branch` and `pattern_branch_names_for_error` contain near-duplicate logic

- **Lines 2473-2624** and **lines 2626-2695**: These two functions share almost identical `eval_dep_len` helper logic. Consider extracting a shared helper.
