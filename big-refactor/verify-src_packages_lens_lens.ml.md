# Verification: src/packages/lens/lens.ml

## File: src/packages/lens/lens.ml

### Finding: Function too long — filter_lens_set_impl (Original line: 298-474)
**Actual line**: 298-474
**Status**: CONFIRMED
**Evidence**: `filter_lens_set_impl` spans 176 lines with 6 top-level match arms (VList, VVector, VDataFrame, VPipeline, catch-all, arity error). Each arm has its own logic for building a mask and applying replacements.
**Verdict**: At 176 lines, the function significantly exceeds the 80-line guideline. The function is well-structured with clear per-type handling, but could benefit from extraction.
**Better fix**: Extract the `build_mask` helper and each data-type arm into separate functions.

---

### Finding: Exception-based control flow with List.assoc (Original line: 681-694)
**Actual line**: 681-694
**Status**: CONFIRMED
**Evidence**: 
```ocaml
(try
  let get_fn = List.assoc "get" items in
  let set_fn = List.assoc "set" items in
  ...
with Not_found -> Error.type_error "Lens missing get/set")
```
Uses `try/with` on `List.assoc` instead of the safer `List.assoc_opt`.
**Verdict**: Using exceptions for control flow is an OCaml anti-pattern when `List.assoc_opt` is available. The `Not_found` exception from `List.assoc` could also be raised from other calls inside the `try` block (e.g., the eval calls), but the review's concern is specifically about using `List.assoc` here.
**Better fix**: Replace with `match List.assoc_opt "get" items, List.assoc_opt "set" items with Some get_fn, Some set_fn -> ... | _ -> ...`.

---

### Finding: Silent skip when row index exceeds column length (Original line: 189)
**Actual line**: 189
**Status**: CONFIRMED
**Evidence**: `if i < Array.length vals then vals.(i) <- new_val;` — if the column array is accidentally shorter than `nrows`, the assignment is silently skipped. The index `i` was validated against `nrows` (line 176), and `vals` is derived from the column with `column_to_values`, so in a consistent DataFrame these lengths match.
**Verdict**: This would only fire with an internally inconsistent DataFrame (which shouldn't happen under normal operations). The fix suggested by the review (making it an assertion) is reasonable from a defense-in-depth perspective.
**Better fix**: Add an assertion or explicit error: `if i >= Array.length vals then Error.type_error ...`.

---

### Finding: List.nth on line 434 relies on caller invariants (Original line: 434)
**Actual line**: 434
**Status**: CONFIRMED
**Evidence**: `List.nth pipe.p_nodes i` — index `i` comes from `build_mask` which iterates `0..n-1` where `n = List.length pipe.p_nodes`. No local bounds check exists.
**Verdict**: Safe under current invariants, but fragile under refactoring. `List.nth_opt` would be more defensive.
**Better fix**: Use `List.nth_opt` with a `match` that returns an error on `None`.

---

### Finding: List.nth on line 117 is guarded (Original line: 116-117)
**Actual line**: 116-117
**Status**: FALSE_POSITIVE — review marked as INFO, not a finding to fix
**Evidence**: The review states "List.nth on line 117 is guarded" and says "None needed." for the fix. This confirms it's a non-issue.
**Verdict**: The review itself acknowledges this is safe. No action needed.
**Better fix**: None needed (as confirmed by the review).

---

### Finding: Dead code — `over_fn` closure in register (Original line: 778-793)
**Actual line**: 778-793
**Status**: FALSE_POSITIVE — `over_fn` is NOT dead code
**Evidence**: Line 778-782 defines `over_fn`, and line 793 registers it: `Env.add "over" (make_builtin_named ~name:"over" 3 over_fn)`. The review incorrectly claims this is dead code.
**Verdict**: `over_fn` IS used — it is passed directly to `Env.add` on line 793. The review's claim of dead code is incorrect. However, the review's secondary observation about inconsistency (using `make_builtin_named` instead of `make_l_builtin`) is valid.
**Better fix**: The review's alternate suggestion to use `make_l_builtin` for consistency could be considered, but the code is not dead as claimed.
