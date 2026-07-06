# Review: src/packages/stats/math_utils.ml

**Lines**: 498
**Severity summary**: 1 critical, 1 warning, 1 info

---

## CRITICAL: Array access on potentially-empty matrix in mat_mul and mat_vec_mul

- **Line 469**: `Array.length a.(0)` in `mat_mul` — If the input matrix `a` has zero rows (`Array.length a = 0`), then `a.(0)` raises `Invalid_argument "index out of bounds"`. The function signature `mat_mul a b` does not document that `a` must be non-empty.

  **Fix**: Add an explicit empty-matrix check at the start:
  ```ocaml
  let m = Array.length a in
  if m = 0 then [||]
  else
    let n = Array.length a.(0) in
    ...
  ```

- **Line 484**: `Array.length a.(0)` in `mat_vec_mul` — Same issue.

  **Fix**: Same as above.

## WARNING: Polymorphic compare on float arrays in quantile_array

- **Line 370**: `Array.sort compare sorted` — Uses polymorphic `compare` on an array of floats. This is not NaN-safe: if the input contains `NaN`, the behavior of `compare` is undefined, and `NaN` values could appear anywhere in the sorted array, producing incorrect quantile results.

  **Fix**: Use a NaN-safe float comparator:
  ```ocaml
  Array.sort (fun a b -> Float.compare a b) sorted
  ```

## INFO: solve_and_invert uses partial pivoting with hardcoded epsilon

- **Lines 439, 450**: Hardcoded `1e-14` threshold for singularity detection in Gaussian elimination. This is a reasonable default for double-precision arithmetic, but it may be too strict for extremely ill-conditioned matrices or too lenient for very small well-conditioned ones.

  **Fix**: Consider making the epsilon a parameter or documenting the assumption. No functional issue.
