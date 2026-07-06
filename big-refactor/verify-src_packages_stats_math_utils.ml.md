# Verification: review-src_packages_stats_math_utils.ml.md → src/packages/stats/math_utils.ml

## File: src/packages/stats/math_utils.ml
### Finding: Array access on potentially-empty matrix in mat_mul (Original line: 469)
**Actual line**: 469 (`let n = Array.length a.(0) in`)
**Status**: CONFIRMED
**Evidence**: If `a` has zero rows (`Array.length a = 0`), then `a.(0)` raises `Invalid_argument "index out of bounds"`. There is no empty-matrix guard before this access. Neither the function signature nor any precondition check prevents this.
**Verdict**: A raw OCaml exception from user input is a violation of AGENTS.md safety rules. Should return `None` or an error for empty matrices.
**Better fix**: Add `let m = Array.length a in if m = 0 then [||] else let n = Array.length a.(0) in ...`

---

## File: src/packages/stats/math_utils.ml
### Finding: Array access on potentially-empty matrix in mat_vec_mul (Original line: 484)
**Actual line**: 484 (`let n = Array.length a.(0) in`)
**Status**: CONFIRMED
**Evidence**: Same pattern as `mat_mul` — no empty-matrix check before accessing `a.(0)`.
**Verdict**: Same risk as above.
**Better fix**: Same pattern as mat_mul.

---

## File: src/packages/stats/math_utils.ml
### Finding: Polymorphic compare on float arrays in quantile_array (Original line: 370)
**Actual line**: 370 (`Array.sort compare sorted;`)
**Status**: CONFIRMED
**Evidence**: `sorted` is a `float array` (created via `Array.copy xs` where `xs` is a `float array`). `compare` is the polymorphic comparison function, which is not NaN-safe: `compare nan x` behavior is unpredictable and may produce wrong sort order for arrays containing NaN.
**Verdict**: Should use `Float.compare` for NaN-safe float ordering.
**Better fix**: `Array.sort (fun a b -> Float.compare a b) sorted`

---

## File: src/packages/stats/math_utils.ml
### Finding: solve_and_invert uses partial pivoting with hardcoded epsilon (Original lines: 439, 450)
**Actual line**: 439, 450 (`if !max_val < 1e-14`, `if Float.abs aug.(i).(i) < 1e-14`)
**Status**: CONFIRMED (INFO)
**Evidence**: `1e-14` is reasonable for double-precision arithmetic but may be too strict for ill-conditioned matrices or too lenient for well-conditioned ones.
**Verdict**: Review correctly identifies this as a design note, not a bug. No action needed.
