# Review: src/packages/math/ndarray.ml

**Lines**: 473
**Severity summary**: 0 critical, 1 warning, 1 info

---

## WARNING: Raw `invalid_arg` exceptions in shape_product

- **Line 13**: `invalid_arg "shape dimensions must be strictly positive"` and line 17: `invalid_arg "shape product: integer overflow computing total size"` are raised inside `shape_product`. Both call sites wrap this in `try ... with Invalid_argument msg -> Error.make_error ValueError msg` (lines 120–121 and 135–136), so these are always caught in practice. However, per AGENTS.md rule #3, user-facing code should return `VError` directly rather than relying on try/with to catch raw exceptions.

  **Fix**: Make `shape_product` return a `(int, string) result`:
  ```ocaml
  let shape_product shape =
    let rec loop acc = function
      | [] -> Ok acc
      | d :: rest when d <= 0 ->
          Error "shape dimensions must be strictly positive"
      | d :: rest ->
          let max_allowed = max_int / d in
          if acc > max_allowed then
            Error "shape product: integer overflow"
          else
            loop (acc * d) rest
    in
    loop 1 (Array.to_list shape)
  ```
  Then use `Result.bind` at call sites to convert the error string to `VError`.

---

## INFO: Float equality in matrix_inverse pivot check

- **Line 227**: `if Float.abs to_factor > 0.0` — comparing a float against literal `0.0` in Gaussian elimination. This is standard practice for this algorithm and is acceptable because the value is a result of subtraction rather than an arbitrary floating-point computation. However, the main singularity check (line 212: `!pivot_abs < eps`) already uses an epsilon of `1e-12`, so this `0.0` comparison is only reached for non-singular matrices.

  **Fix**: Consider using `eps` (`1e-12`) consistently here as well for symmetry, though the functional impact is negligible.

No other issues found. All array accesses are properly bounds-checked against shapes, pattern matches are exhaustive, and docstrings follow the `--#` convention.
