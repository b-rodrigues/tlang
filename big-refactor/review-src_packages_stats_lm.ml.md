# Review: src/packages/stats/lm.ml

**Lines**: 488
**Severity summary**: 1 critical, 2 warning, 1 info

---

## CRITICAL: Unvalidated List.map2 on potentially-mismatched arrays

- **Line 86**: `List.map2 (fun name value -> ...) result.term_names (Array.to_list result.coefficients)` — If `result.term_names` and `result.coefficients` have different lengths, `List.map2` raises `Invalid_argument`. These come from `Arrow_owl_bridge.lm_result`, which should produce consistent arrays, but there's no defensive guard.

  **Fix**: Add an assertion or length check before the call:
  ```ocaml
  let n = Array.length result.coefficients in
  assert (List.length result.term_names = n);
  ```

- **Line 92**: Same pattern: `List.map2 (fun name value -> ...) result.term_names (Array.to_list result.std_errors)`.

  **Fix**: Same as above.

## WARNING: Float equality checks

- **Line 185**: `Array.for_all (fun w -> w = 0.0) ws` — Uses polymorphic `=` on floats. Comparing floats for exact equality to 0.0 is a well-known anti-pattern (0.0 may be -0.0, or values that should be zero may be small non-zero due to floating-point arithmetic).

  **Fix**: Use `Float.equal w 0.0` or a small epsilon comparison:
  ```ocaml
  Array.for_all (fun w -> Float.abs w < 1e-15) ws
  ```

## WARNING: Duplicate function name in stats_package

- **Line 140**: `"add_diagnostics"` appears twice in the `stats_package` function list (once at position 8, once at position 18). This is not a code error (it's just a string in a list), but it's confusing and suggests a copy-paste issue.

  **Fix**: Remove the duplicate entry from `src/packages/core/packages.ml` line 140.

## INFO: Row iteration with ref accumulator for NA detection

- **Lines 128–141, 142–157**: `float_array_of_numeric_column` uses a recursive loop with `ref` accumulator. This is acceptable per the AGENTS.md rule on mutable state ("when strictly necessary"). The NA check requires early exit on first None, which is harder with `Array.fold_left`.

  **Fix**: No action needed.
