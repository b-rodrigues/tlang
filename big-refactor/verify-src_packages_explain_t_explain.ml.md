# Verification: review-src_packages_explain_t_explain.ml.md → src/packages/explain/t_explain.ml

## File: src/packages/explain/t_explain.ml
### Finding: Unvalidated List.assoc on value_columns (Original lines: 135-138)
**Actual line**: 135-138 (`List.assoc "node" value_columns`, etc.)
**Status**: CONFIRMED
**Evidence**: The guard at lines 131-133 checks `List.map fst value_columns = ["node"; "status"; "code"; "message"]`, which guarantees all four keys exist. Under current code, `List.assoc` cannot raise. However, this is fragile: any future change to the guard condition or `Arrow_bridge.table_to_value_columns` column ordering could break the implicit contract.
**Verdict**: The review correctly identifies a fragility concern. The `List.assoc` calls are technically safe today but would silently crash if the guard is modified.
**Better fix**: Replace with `List.assoc_opt` + explicit error handling, making the safety explicit rather than relying on the guard.

---

## File: src/packages/explain/t_explain.ml
### Finding: Function too long (do_explain) (Original lines: 52-463)
**Actual line**: 52-463
**Status**: CONFIRMED
**Evidence**: `do_explain` is ~411 lines and handles 18+ value variants with deeply nested logic for DataFrame diffs, VLambda parameter inference, VBuiltin docstring parsing, and VError location formatting. Wildcard catch-all at line 458 hides missing variant coverage.
**Verdict**: This is a maintainability concern. The length makes it difficult to review, test, and extend. The wildcard catch-all at line 458 would prevent the compiler from warning about missed variants if a new variant is added to `Ast.value`.
**Better fix**: Extract per-type handler functions (`explain_dataframe`, `explain_pipeline`, etc.).

---

## File: src/packages/explain/t_explain.ml
### Finding: Non-standard List.filteri usage (Original line: 118)
**Actual line**: 118 (`List.filteri (fun i _ -> i < example_n) items`)
**Status**: FALSE_POSITIVE
**Evidence**: `List.filteri` was added to the OCaml standard library in version 4.10.0 (October 2020). This project uses a Nix flake with a modern OCaml toolchain, making `List.filteri` a standard, available function. The code compiles and passes tests.
**Verdict**: The reviewer incorrectly assumed `List.filteri` is non-standard. It has been part of OCaml's stdlib since 4.10.

---

## File: src/packages/explain/t_explain.ml
### Finding: List.hd on String.split_on_char result (Original line: 393)
**Actual line**: 393 (`List.hd (String.split_on_char ' ' (String.trim right))`)
**Status**: CONFIRMED (INFO)
**Evidence**: `String.split_on_char` always returns a non-empty list (minimum `[""]`), so `List.hd` is safe. However, this property is subtle and not obvious at first glance.
**Verdict**: The review correctly identifies this as a valid but fragile pattern. The pattern match alternative would be clearer but is not required for correctness.
