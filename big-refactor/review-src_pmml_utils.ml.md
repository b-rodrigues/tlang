# Review: src/pmml_utils.ml

**Lines**: 901
**Severity summary**: 1 critical, 2 warning, 1 info

---

## CRITICAL: raise Invalid_argument in XML parsing reachable from user input

- **Line 675**: `raise (Invalid_argument "Required PMML attribute 'name' missing in <NumericPredictor>")` in `parse_table_body`. This is inside a user-facing PMML parser — anyone loading a malformed PMML file can trigger this `raise`, which bypasses the structured `VError` path and produces an OCaml `Failure`/`Invalid_argument` exception.

  **Fix**: Return an error value or use a structured error path instead of `raise`. The outer `try/with exn ->` at line 900 does catch it and wraps it in an `Error` string, so the function signature `parse_pmml -> (value, string) result` is preserved. However, the intermediate `raise` breaks the control flow in `parse_table_body` and could leave mutable `ref` cells in inconsistent states.

- **Line 719**: `raise (Invalid_argument "Required PMML attribute 'intercept' missing in <RegressionTable>")` — Same issue.

  **Fix**: Same as above.

## WARNING: Catch-all exception handler hides JSON parse errors

- **Line 756**: `try ... with _ -> ()` — When parsing GLMStats JSON from an Extension element (`Yojson.Safe.from_string`), any parse error is silently swallowed with `()`. The user gets no indication that GLM-specific stats were expected but couldn't be parsed.

  **Fix**: At minimum, `prerr_endline` the parse error. Or propagate the error to the caller.

## WARNING: Fallback empty Elem construction used as sentinel

- **Lines 238, 417–418, 519–520**: `Elem ("Node", [], [])` used as a fallback/placeholder when the expected element is not found in the XML tree. This fallback element is then passed to `parse_node`, which will return `Error "Expected <Node> element in TreeModel."` — so the error path is correct, but constructing a dummy element just to produce an error is roundabout.

  **Fix**: Directly return `Error` when the element is missing instead of constructing a dummy and relying on downstream validation to catch it.

## INFO: contains_substring allocates and lowercases entire strings

- **Lines 105–115**: `contains_substring` lowercases both `hay` and `needle` and then searches. For PMML files with thousands of elements, this could be called many times on long attribute values.

  **Fix**: Minor performance concern. No change needed unless profiling shows it's a bottleneck.
