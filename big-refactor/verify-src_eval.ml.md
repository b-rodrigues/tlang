# Verification Report: src/eval.ml

---

## CRITICAL: Use of `List.hd` — Line 1998

### Finding: List.hd on guarded non-empty list (Original line: 1998)

**Actual line**: 1998
**Status**: CONFIRMED

**Evidence**: 
```ocaml
1977:       if !changed then propagate next else next
1978:     in
1979:     propagate desugared_nodes
1980:   in
1981:   let desugared_nodes = List.map (fun (name, un) ->
...
1997:     if offenders <> [] then
1998:       let offender = List.hd offenders in
1999:       let offender_runtime = match List.assoc_opt offender runtime_mapping with Some r -> r | None -> "Unknown" in
```

`List.hd` is a partial function. Though guarded by `offenders <> []` at line 1997, the pattern should use matching instead.

**Verdict**: The code is functionally safe (non-empty check on line 1997 precedes usage), but `List.hd` is a partial function that OCaml style guidelines discourage. Using a pattern match would be more idiomatic and remove the latent risk if the guard were ever removed.

---

## CRITICAL: Use of `List.hd` — Line 2006

### Finding: List.hd on guarded non-empty list (Original line: 2006)

**Actual line**: 2006
**Status**: CONFIRMED

**Evidence**:
```ocaml
2003:   ) desugared_nodes in
2004: 
2005:   if validation_errors <> [] then
2006:     Error.make_error StructuralError (List.hd validation_errors)
2007:   else begin
```

Same pattern: guarded by line 2005 but uses the partial `List.hd`.

**Verdict**: CONFIRMED. Same fix applies — use pattern matching.

---

## CRITICAL: Unvalidated `List.nth` at Line 2538

### Finding: `List.nth` with runtime-validated but unprovable bounds (Original line: 2538)

**Actual line**: 2538
**Status**: NEEDS REVISION

**Evidence**:
```ocaml
2532:   let eval_dep_at_index dep index =
2533:     match List.assoc_opt dep p.Ast.p_exprs with
2534:     | Some expr ->
2535:         (try
2536:            match eval_expr (ref env) expr with
2537:            | Ast.VList items ->
2538:                if index >= 0 && index < List.length items then snd (List.nth items index)
2539:                else Ast.VNA Ast.NAGeneric
```

**Verdict**: The bounds check (`index >= 0 && index < List.length items`) does validate safety at runtime. However, the review's proposed fix (`List.nth_opt`) is strictly better: it eliminates the latent risk entirely and removes one line of double-checking. Note that this code is already wrapped in `try ... with _ -> Ast.VNA Ast.NAGeneric` at lines 2535/2549, so even if the bounds check fails, it won't crash. But using `List.nth_opt` would make the code simpler and more robust.

**Better fix**:
```ocaml
| Ast.VList items ->
    (match List.nth_opt items index with
     | Some (_, v) -> v
     | None -> Ast.VNA Ast.NAGeneric)
```

---

## WARNING: `eval_expr` function too long (Original: lines 996-1575)

### Finding: ~580-line main evaluation dispatch function

**Actual line**: 996 through 1575
**Status**: CONFIRMED (stylistic/architectural)

**Evidence**: `eval_expr` spans from line 996 (`and eval_expr (env_ref : environment ref) (expr : Ast.expr) : value =`) to line 1575 (`attach_expr_location expr result`), approximately 580 lines. The node/pipeline construction section (lines 1099-1556) is ~457 lines handling `node`, `pyn`, `rn`, `jln`, `qn`, `shn` call logic with sub-lookups.

**Verdict**: The function is indeed long and complex. The review's suggestion to extract the node-construction path and sub-lookups (`lookup_env_vars`, `lookup_runtime_args`, etc.) into separate functions is reasonable but would be a significant refactor touching many call sites. This is a valid architectural concern, not a correctness bug.

---

## WARNING: `eval_pipeline` function too long (Original: lines 1726-2086)

### Finding: ~360-line pipeline evaluation function

**Actual line**: 1726 through 2086
**Status**: CONFIRMED (stylistic/architectural)

**Evidence**: `eval_pipeline` spans from line 1726 to line 2086, containing:
- `desugar_node` inner function (lines 1847-1888) — but note: this isn't just a small helper
- `compute_deps` (lines 1916-1956)
- No-op propagation (lines 1962-1980)
- Cross-runtime validation (lines 1982-2006)
- Topological sort and result construction

**Verdict**: CONFIRMED. The function does many things and would benefit from decomposition. However, the `desugar_node` is actually an **inner function** already (not a top-level extractable helper in the current design), and extracting `compute_deps` would require threading multiple context variables. Not a correctness issue.

---

## WARNING: `eval_call` function too long (Original: lines 3059-3414)

### Finding: ~355-line call evaluation function

**Actual line**: 3059 through 3414
**Status**: CONFIRMED (stylistic/architectural)

**Evidence**: `eval_call` from line 3059 to line 3414 contains NSE argument transformation, the `rm()` special case, `process_args_spliced` recursion, `apply_lambda` inner function, and the main `match fn_val` dispatch.

**Verdict**: CONFIRMED. `process_args_spliced` (lines 3190-3233) and `apply_lambda` (lines 3271-3336) are inner functions within `eval_call`'s body. The review's suggestion to extract them is reasonable.

---

## WARNING: `eval_dot_access_val` deeply nested (Original: lines 2781-2971)

### Finding: Up to 6 levels of nested match/if in VDict branch

**Actual line**: 2781 through 2971
**Status**: CONFIRMED

**Evidence**: The VDict branch (lines 2796-2849) contains nested matches for `__partial_dot_df__`, `__partial_dot_pipeline__`, `__partial_dot_dict__`, and fallback key prefix matching — up to 6 levels deep at the deepest point (line 2837-2849).

**Verdict**: CONFIRMED. The control flow is genuinely hard to follow due to the deep nesting. Extracting the partial dot-access logic into named helper functions would improve readability.

---

## WARNING: Catch-all `with _ ->` at Lines 2500, 2549, 2637

### Finding: Overly broad exception handling

**Actual lines**: 2500, 2549, 2637
**Status**: CONFIRMED

**Evidence**:
- **Line 2500**: `with _ -> None` inside `eval_dep_len` — catches all exceptions silently
- **Line 2549**: `with _ -> Ast.VNA Ast.NAGeneric` inside `eval_dep_at_index` — same
- **Line 2637**: `with _ -> None` inside `pattern_branch_names_for_error` — same

**Verdict**: CONFIRMED. All three catch-alls are in "best effort" contexts (optional/branch-level computations) where returning `None`/`NAGeneric` is the intended fallback. However, `with _ ->` could mask real programming errors (e.g., `Match_failure`, `Not_found` from refactoring mistakes). At minimum, this should catch `Ast.Error _ | Failure _ | Not_found | Match_failure _` to allow true bugs to surface, or validate inputs before calling `eval_expr`.

---

## WARNING: Global mutable state (Original: lines 205-849)

### Finding: Multiple global `ref` variables

**Actual lines**: 205, 207-209, 216, 220-224, 228, 849
**Status**: CONFIRMED (stylistic/architectural)

**Evidence**: All refs are present at the cited lines:
- `show_warnings` at line 205
- `global_warnings` at lines 207-209
- `current_node_warning_emitter` at line 216
- `last_node_diagnostics`, `last_pipeline_exprs`, `last_evaluated_node_name`, `current_node_suppression_requested` at lines 220-224
- `pipeline_construction_mode` at line 228
- `current_imports` at line 849

**Verdict**: CONFIRMED. The review acknowledges these are necessary for the current architecture. Threading them through function parameters or encapsulating in a record would be cleaner but would require significant redesign. Not a correctness bug.

---

## INFO: `List.nth` with validated bounds (Original: lines 1730-1731)

### Finding: `List.nth` guarded by length check

**Actual lines**: 1730-1731
**Status**: CONFIRMED

**Evidence**:
```ocaml
1727:   (match List.find_opt (fun (name, _) ->
1728:     let parts = String.split_on_char '_' name in
1729:     List.length parts >= 3
1730:     && List.nth parts (List.length parts - 2) = "branch"
1731:     && let last = List.nth parts (List.length parts - 1) in
```

**Verdict**: CONFIRMED. Both `List.nth` calls are guarded by `List.length parts >= 3` on line 1729, so they are safe. Same pattern as the critical finding — `List.nth_opt` would be more idiomatic.

---

## INFO: `strip_dollar_prefix` duplication (Original: line 267)

### Finding: Duplicated across modules

**Actual line**: 267
**Status**: FALSE POSITIVE

**Evidence**: `strip_dollar_prefix` is defined at eval.ml line 267 and used only within eval.ml (line 2991). The review claims it is "also defined in `src/packages/pipeline/pipeline_dag_ops.ml` and possibly elsewhere", but a grep of the entire `src/` tree found only two occurrences, both in `eval.ml`. There is no external duplication.

**Verdict**: FALSE POSITIVE — no duplication exists. However, the suggestion to move it to a shared utility module remains a reasonable forward-looking recommendation if it ever becomes needed elsewhere.

---

## INFO: Duplicate logic in `try_lazy_expand_branch` and `pattern_branch_names_for_error` (Original: lines 2473-2695)

### Finding: Near-identical `eval_dep_len` helpers

**Actual lines**: 2490-2531 and 2627-2668
**Status**: CONFIRMED

**Evidence**: `eval_dep_len` is defined inside `try_lazy_expand_branch` (lines 2490-2531) and again inside `pattern_branch_names_for_error` (lines 2627-2668). The two implementations are structurally identical: both handle `List.assoc_opt` lookup, `eval_expr` in try-block, `VList`/`VVector`/`VDataFrame` length extraction, fallback to `p_patterns` recursive length computation with `PatternMap`/`PatternCross`/`PatternSlice`/`PatternHead`/`PatternTail`/`PatternSample`. The only difference is the environment used: `ref env` vs `ref Ast.Env.empty`.

**Verdict**: CONFIRMED. These are nearly byte-for-byte duplicates. A shared helper parameterized on the environment would eliminate the duplication.

