# Review: src/packages/lens/lens.ml

**Lines**: 795
**Severity summary**: 0 critical, 4 warning, 2 info

---

## WARNING: Function too long — filter_lens_set_impl

- **Line 298-474**: `filter_lens_set_impl` is ~176 lines with 6 top-level match arms (VList, VVector, VDataFrame, VPipeline, catch-all, arity error). Each arm has its own logic for masking and replacement.

  **Fix**: Extract the `build_mask` helper (already present as a nested function) and each data-type arm into a separate function (e.g., `filter_lens_set_list`, `filter_lens_set_vector`, `filter_lens_set_dataframe`, `filter_lens_set_pipeline`).

## WARNING: Exception-based control flow with List.assoc

- **Line 681-694**: `over_val` uses `try let get_fn = List.assoc "get" items in ... with Not_found -> ...` instead of `List.assoc_opt`.

  **Fix**: Replace with `match List.assoc_opt "get" items, List.assoc_opt "set" items with Some get_fn, Some set_fn -> ... | _ -> ...`.

## WARNING: Silent skip when row index exceeds column length

- **Line 189**: `if i < Array.length vals then vals.(i) <- new_val;` — if the column array is shorter than `nrows`, the assignment is silently skipped. While `i` was validated against `nrows` (line 176), an inconsistent DataFrame (e.g., from internal corruption) would silently lose data.

  **Fix**: Make this an assertion or explicit error: `if i >= Array.length vals then Error.type_error ...`.

## WARNING: List.nth on line 434 relies on caller invariants

- **Line 434**: `List.nth pipe.p_nodes i` — the index `i` comes from `build_mask` which iterates `0..n-1` where `n = List.length pipe.p_nodes`, so it is safe. But there is no local bounds check; any future refactor that changes `build_mask`'s iteration range could cause a `Failure` at runtime.

  **Fix**: Use `List.nth_opt` with a `match` that returns an error on `None`.

## INFO: List.nth on line 117 is guarded

- **Line 116-117**: `if i < 0 || i >= len then Error.index_error i len else let (_, v) = List.nth items i in v` — the bounds check makes `List.nth` safe. This is acceptable.

  **Fix**: None needed.

## INFO: Dead code — `over_fn` closure in register

- **Line 778-782**: `over_fn` is defined as a local closure but then `over` is registered via `Env.add "over" (make_builtin_named ~name:"over" 3 over_fn)` instead of through `make_l_builtin`. This double-path registration (one closure via `Env.add`, the rest via `make_l_builtin`) is inconsistent but not dead.

  **Fix**: Use `make_l_builtin "over" 3 over_impl` for consistency with the other registrations, or remove `over_fn` if unused.
