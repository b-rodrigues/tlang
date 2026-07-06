# Verification: review-src_packages_colcraft_expand.ml.md → src/packages/colcraft/expand.ml

## File: src/packages/colcraft/expand.ml
### Finding: Unvalidated List.nth access (Original line: 131)
**Actual line**: 131 (`List.nth combos_arr.(0) i`)
**Status**: CONFIRMED
**Evidence**: The loop index `i` comes from `List.mapi` over `column_names` (line 121). `combos_arr.(0)` is a single combo list whose length equals `List.length column_names` (each combo has one element per column). The `nrows > 0` guard at line 131 ensures `combos_arr` is non-empty, and `i < List.length column_names` is guaranteed by `List.mapi`. So `List.nth` is technically safe, but the review correctly notes this is inconsistent with the surrounding code: line 123 in the same `Array.init` uses `List.nth_opt`.
**Verdict**: The review correctly identifies that line 131 uses `List.nth` while line 123 in the same `Array.init` block uses `List.nth_opt`. The inconsistency is real and the `List.nth` call is fragile. Under current invariants it cannot fail, but a future change to `column_names` or combo construction could introduce a mismatch without the compiler warning.
**Better fix**: Replace with `List.nth_opt combos_arr.(0) i` and handle the `None` case (fall back to `VNA NAGeneric`), matching the safe pattern already used at line 123.

---

## File: src/packages/colcraft/expand.ml
### Finding: Code duplication with t_complete.ml (Original lines: 8-13)
**Actual line**: 8-13 (cartesian function), 4-6 (expand_input type)
**Status**: CONFIRMED (INFO)
**Evidence**: Both `expand.ml` and `t_complete.ml` define identical copies of:
- The `expand_input` type (lines 4-6 in expand.ml, lines 7-9 in t_complete.ml)
- The `cartesian` function (lines 8-13 in expand.ml, lines 132-138 in t_complete.ml)

**Verdict**: The review correctly identifies code duplication. Extracting these into a shared module would eliminate the redundancy and ensure any fixes apply to both consumers.
**Better fix**: Move `cartesian`, `expand_input`, and shared helpers to `colcraft/expand_common.ml`.
