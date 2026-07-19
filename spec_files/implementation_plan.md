# Implementation Plan - Calculated Suggested-Fix Confidence Levels

This plan details the implementation of **Path C (Hybrid Approach)** to transition suggested fixes from static serialization constants to dynamically calculated values based on compiler signals (edit distance, candidate uniqueness, schema chain integrity).

---

## User Review Required

> [!IMPORTANT]
> - All variants of `suggested_fix` (except `NoFix`) will be modified to include their underlying calculation metrics (e.g. `chain_broken: bool`, `edit_distance: int`, `is_unique: bool`) along with the pre-computed `confidence` value.
> - `Ast.suggest_name` remains unchanged for backward compatibility to avoid touching the tree-walking evaluator (`eval.ml`), but a new `Ast.suggest_names_with_scores` function will be added.

---

## Proposed Changes

### AST Layer

#### [MODIFY] [ast.ml](file:///home/brodrigues/Documents/repos/tlang/src/ast.ml)
- Add `suggest_names_with_scores : string -> string list -> (string * int) list` returning all matches within Levenshtein range, sorted.
- Re-implement `suggest_name` in terms of `suggest_names_with_scores` to ensure backward compatibility.

### Diagnostics Layer

#### [MODIFY] [diagnostics.ml](file:///home/brodrigues/Documents/repos/tlang/src/diagnostics.ml)
- Define `type confidence = High | Medium | Low`.
- Update `type suggested_fix` constructor payloads to include `confidence` and their respective signal fields (`chain_broken`, `edit_distance`, `is_unique`).
- Add helper functions `confidence_for_cast` and `confidence_for_typo` to centralize signal-to-label threshold mapping.
- Update `suggested_fix_to_yojson` and `suggested_fix_of_yojson` to serialize and parse these new fields.
- Update `of_verror` to construct `Suggest_identifier` and `Add_node_arg` using dynamic signals.

### Schema Checking Layer

#### [MODIFY] [schema_check.ml](file:///home/brodrigues/Documents/repos/tlang/src/schema_check.ml)
- Add tracking for schema chain integrity (e.g., track whether the current schema was derived from a chain containing an unknown/custom function).
- Update construction of `Cast` fixes (lines 431, 637) to determine `chain_broken` and compute `confidence`.
- Update construction of `Rename_column` fixes (line 494) to calculate Levenshtein distance and uniqueness against candidates.

### Mechanical Fix Application Layer

#### [MODIFY] [fix.ml](file:///home/brodrigues/Documents/repos/tlang/src/fix.ml)
- Update `suggested_fix` pattern matching in `apply_fix` and `apply_fixes` to match the new constructor payloads.

#### [MODIFY] [t_fix.ml](file:///home/brodrigues/Documents/repos/tlang/src/packages/pipeline/t_fix.ml)
- Update `suggested_fix` pattern matching in `format_fix_result` to match the new constructor payloads.

### Unit Tests

#### [MODIFY] [test_check.ml](file:///home/brodrigues/Documents/repos/tlang/tests/test_check.ml)
- Update test cases constructing `suggested_fix` records.
- Add test cases explicitly checking that confidence degrades correctly under chain-broken or ambiguous typo scenarios.

#### [MODIFY] [test_fix.ml](file:///home/brodrigues/Documents/repos/tlang/tests/test_fix.ml)
- Update test cases constructing `suggested_fix` records.

---

## Verification Plan

### Automated Tests
- Run `dune build` and `dune runtest` to ensure the compilation is successful and all unit tests pass.
- Run the new test blocks in `test_check.ml` to verify dynamic confidence scoring under various scenarios.
