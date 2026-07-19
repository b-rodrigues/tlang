# Implementation Plan - Calculated Suggested-Fix Confidence Levels

This plan details the implementation of **Path C (Hybrid Approach)** to transition suggested fixes from static serialization constants to dynamically calculated values based on compiler signals (edit distance, candidate uniqueness, schema chain integrity).

---

## User Review Required

> [!IMPORTANT]
> - **Smart Constructors:** To prevent representation drift between raw signals and precomputed `confidence` values, variants of `suggested_fix` will be created *only* via centralized smart constructors (e.g. `Diagnostics.make_cast_fix`, `Diagnostics.make_rename_column_fix`). Exposing raw record construction of fixes is disallowed.
> - **Centralized Resolution:** The signal-to-label threshold mapping is isolated inside `Diagnostics.confidence_of_signals` (or helper functions) in `diagnostics.ml`, allowing easy threshold tuning and unit testing.
> - **JSON Serialization Contract:** The JSON diagnostics schema remains clean and backward-compatible: it will serialize the precomputed `"confidence"` string, but will *not* expose the internal OCaml signal fields (`chain_broken`, `edit_distance`, `is_unique`) to keep the public API minimal.
> - **of_yojson Defaults:** When deserializing a suggested fix from JSON, internal signal fields that are absent in the JSON representation will be assigned safe defaults (`chain_broken = false`, `edit_distance = 0`, `is_unique = true`). Round-trip unit tests will assert the equality of serialized fields (like `confidence` and syntactic parameters) rather than full record equality.
> - **Add_node_arg Status:** `Add_node_arg` will stay a hardcoded `Medium` confidence for this iteration (due to parsing error strings without full DAG context).
> - **Sequenced Delivery:** The implementation is divided into two sequential, low-risk phases:
>   - **Phase 1:** AST definitions, `diagnostics.ml` smart constructors, unit tests with mock signals.
>   - **Phase 2:** `schema_check.ml` wiring to supply real compiler signals.

---

## Signal-to-Label Mapping Logic (Truth Table)

The centralized helper functions in `diagnostics.ml` will map compiler signals to `confidence` labels according to the following specification:

| Fix Type | Signals | Resulting Confidence |
|---|---|---|
| **`Cast`** | `chain_broken = false` | `High` |
| | `chain_broken = true` | `Medium` |
| **`Rename_column`** | `edit_distance = 1` and `is_unique = true` | `High` |
| | `edit_distance = 2` and `is_unique = true` | `Medium` |
| | `edit_distance = 1` and `is_unique = false` | `Medium` (best candidate score is high but ambiguous) |
| | `edit_distance = 2` and `is_unique = false` | `Low` |
| | `edit_distance >= 3` | `Low` |
| **`Suggest_identifier`** | `edit_distance = 1` and `is_unique = true` | `High` |
| | `edit_distance = 2` and `is_unique = true` | `Medium` |
| | `edit_distance = 1` and `is_unique = false` | `Medium` |
| | `edit_distance = 2` and `is_unique = false` | `Low` |
| | `edit_distance >= 3` | `Low` |
| **`Add_node_arg`** | *N/A (Heuristic fallback)* | `Medium` |
| **`Run_command`** | *N/A (Heuristic fallback)* | `Low` |

---

## Proposed Changes

### AST Layer

#### [MODIFY] [ast.ml](file:///home/brodrigues/Documents/repos/tlang/src/ast.ml)
- Add `suggest_names_with_scores : string -> string list -> (string * int) list` returning all matches within Levenshtein range, sorted by distance.
- Re-implement `suggest_name` in terms of `suggest_names_with_scores` to ensure 100% backward compatibility with `eval.ml`.

### Diagnostics Layer

#### [MODIFY] [diagnostics.ml](file:///home/brodrigues/Documents/repos/tlang/src/diagnostics.ml)
- Define `type confidence = High | Medium | Low`.
- Update `type suggested_fix` constructor payloads to include `confidence` and their respective signal fields:
  ```ocaml
  type suggested_fix =
    | Cast of { column: string; cast_to: string; target_node: string option; file: string option; line: int option; chain_broken: bool; confidence: confidence }
    | Rename_column of { old_name: string; new_name: string; target_node: string option; file: string option; line: int option; edit_distance: int; is_unique: bool; confidence: confidence }
    | Add_node_arg of { node: string; arg: string; target_node: string option; file: string option; line: int option; confidence: confidence }
    | Suggest_identifier of { name: string; suggestion: string; target_node: string option; file: string option; line: int option; edit_distance: int; is_unique: bool; confidence: confidence }
    | Run_command of { command: string; description: string; target_node: string option; file: string option; line: int option; confidence: confidence }
    | NoFix
  ```
- Expose **smart constructors** to instantiate fixes and calculate confidence:
  - `make_cast_fix ~column ~cast_to ~chain_broken ?target_node ?file ?line ()`
  - `make_rename_column_fix ~old_name ~new_name ~edit_distance ~is_unique ?target_node ?file ?line ()`
  - `make_suggest_identifier_fix ~name ~suggestion ~edit_distance ~is_unique ?target_node ?file ?line ()`
  - `make_add_node_arg_fix ~node ~arg ?target_node ?file ?line ()`
  - `make_run_command_fix ~command ~description ?target_node ?file ?line ()`
- Update `suggested_fix_to_yojson` and `suggested_fix_of_yojson` to serialize and parse the `"confidence"` field while keeping signal fields internal-only.
- Update `of_verror` to construct fixes using the smart constructors.

### Schema Checking Layer

#### [MODIFY] [schema_check.ml](file:///home/brodrigues/Documents/repos/tlang/src/schema_check.ml)
- Track schema chain integrity: `chain_broken` is set to `true` if a schema was derived downstream of any unrecognized or custom function (which drops schema propagation to `[]`).
- Update `Cast` and `Rename_column` fix instantiation to use the new smart constructors, passing calculated signal metrics.

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
- Run `dune build` and `dune runtest` to ensure successful compilation and test execution.
- Add and run specific test scenarios in `test_check.ml` that exercise:
  - `Cast` confidence degradation (`chain_broken = true` $\to$ `Medium` confidence).
  - Typo confidence degradation (`edit_distance = 2` or `is_unique = false` $\to$ `Medium`/`Low` confidence).
  - Round-trip serialization testing: `suggested_fix` parsed back from JSON retains matching semantic fields.
