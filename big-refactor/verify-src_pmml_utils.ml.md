# Verification: review-src_pmml_utils.ml.md → src/pmml_utils.ml

## File: src/pmml_utils.ml
### Finding: raise Invalid_argument in XML parsing reachable from user input (Original line: 675)
**Actual line**: 675 (`raise (Invalid_argument "Required PMML attribute 'name' missing in <NumericPredictor>")`)
**Status**: CONFIRMED
**Evidence**: Line 675 is inside `parse_table_body`, which is called during PMML parsing at line 726. If someone loads a malformed PMML file without a `name` attribute on a `<NumericPredictor>`, this `raise` fires. The outer `try/with exn ->` at line 900 does catch it, so `read_pmml`'s return type `(value, string) result` is preserved. However, `parse_table_body` manipulates `ref` cells (`coeffs`, `intercept`), and an intermediate raise could leave these in an inconsistent state.
**Verdict**: The review correctly identifies that using `raise` for user-input validation breaks the structured error convention. Even though the outer handler catches it, the intermediate `raise` prevents `parse_table_body` from completing cleanly and could leave mutable state partially updated.
**Better fix**: Return an `Error` value from `parse_table_body` instead of raising, and propagate it through the call chain.

---

## File: src/pmml_utils.ml
### Finding: raise Invalid_argument in XML parsing reachable from user input (Original line: 719)
**Actual line**: 719 (`raise (Invalid_argument "Required PMML attribute 'intercept' missing in <RegressionTable>")`)
**Status**: CONFIRMED
**Evidence**: Same pattern as line 675. This raise is inside the top-level `loop()` called by `read_pmml`. The `try/with` at line 900 catches it, but the same `ref`-state concerns apply.
**Verdict**: Same issue. Should return an error value instead of raising.
**Better fix**: Same as above — return `Error` instead of `raise`.

---

## File: src/pmml_utils.ml
### Finding: Catch-all exception handler hides JSON parse errors (Original line: 756)
**Actual line**: 756 (`with _ -> ()`)
**Status**: CONFIRMED
**Evidence**: The `try ... Yojson.Safe.from_string json_s ... with _ -> ()` at lines 753-756 silently swallows any JSON parse error, leaving `glm_stats := None`. If GLM stats are expected but malformed, the user gets no diagnostic.
**Verdict**: The review correctly identifies that silently swallowing parse errors is poor practice. At minimum, a warning should be emitted. No data corruption occurs (the fallback is None), but debugging is made harder.
**Better fix**: At minimum, add `prerr_endline` with the exception. Or propagate the error.

---

## File: src/pmml_utils.ml
### Finding: Fallback empty Elem construction used as sentinel (Original lines: 238, 417-418, 519-520)
**Actual line**: 238 (`| None -> Elem ("Node", [], [])`), 417-418 (same pattern), 519-520 (same pattern)
**Status**: CONFIRMED
**Evidence**: Three locations construct dummy `Elem ("Node", [], [])` when the expected element is not found. These dummy elements are passed to `parse_node` / `parse_tree_model`, which return `Error "Expected <Node> element..."`. The error path is correct but constructed indirectly.
**Verdict**: The review correctly identifies a mildly roundabout error path. The code is functionally correct (a proper error is ultimately returned), but directly returning the error would be clearer.
**Better fix**: Return `Error` directly when the expected element is missing, rather than constructing a dummy element just to trigger downstream validation.

---

## File: src/pmml_utils.ml
### Finding: contains_substring allocates and lowercases entire strings (Original lines: 105-115)
**Actual line**: 105-115
**Status**: CONFIRMED (INFO)
**Evidence**: `contains_substring` lowercases both inputs fully before searching. For PMML files with thousands of elements and long attribute values, this could be called repeatedly.
**Verdict**: Review correctly identifies this as a minor performance note. No correctness issue. No fix needed unless profiling shows it as a bottleneck.
