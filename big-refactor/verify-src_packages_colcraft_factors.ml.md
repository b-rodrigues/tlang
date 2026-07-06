# Verification: review-src_packages_colcraft_factors.ml.md → src/packages/colcraft/factors.ml

## File: src/packages/colcraft/factors.ml
### Finding: Unvalidated x_arr.(i) access in fct_reorder_impl (Original line: 244)
**Actual line**: 244 (`(match x_arr.(i) with ...`)
**Status**: CONFIRMED
**Evidence**: Line 235 sets `n = Array.length f_arr`. The loop at line 240 iterates `for i = 0 to n - 1` using `f_arr.(i)`, but there is no check that `Array.length x_arr >= n`. If `x_arr` is shorter than `f_arr`, accessing `x_arr.(i)` raises `Invalid_argument "index out of bounds"` — a raw OCaml exception that crashes the evaluator instead of returning a `VError`.
**Verdict**: The review correctly identifies a missing length validation. The function accepts `[VVector f_arr; VVector x_arr]` at line 230 but only guards against `f_arr` being empty (line 231), not against length mismatch between the two arrays.
**Better fix**: Add `if Array.length f_arr <> Array.length x_arr then Error.value_error ...` before the loop, and restructure the function to return `Result` instead of `VVector` directly.

---

## File: src/packages/colcraft/factors.ml
### Finding: Unnecessary function alias factor_impl (Original line: 95)
**Actual line**: 95 (`let factor_impl = to_factor_impl`)
**Status**: CONFIRMED
**Evidence**: `to_factor_impl` is only referenced as the RHS of the `factor_impl` binding at line 95. The name `factor_impl` is then registered as `"to_factor"` at line 941. `to_factor_impl` is effectively dead code after the alias.
**Verdict**: This is a minor code hygiene issue. The alias adds indirection without benefit. Either rename `to_factor_impl` to `factor_impl` directly or drop the alias.
**Better fix**: Rename `to_factor_impl` → `factor_impl` and delete line 95.

---

## File: src/packages/colcraft/factors.ml
### Finding: Inconsistent error message style (Original lines: 41, 177, 458, 474, 518)
**Actual line**: Multiple
**Status**: CONFIRMED (INFO)
**Evidence**: Line 41 uses `"to_factor expects at least 1 argument"` (no `Function` prefix, no backticks). Lines 458, 474, 518 use `` Function `foo` expects...`` with backticks. The two styles are inconsistent within the same file.
**Verdict**: The review correctly identifies stylistic inconsistency. Not a correctness bug but worth unifying for maintainability.
**Better fix**: Pick the `Function \`foo\` expects...` style (used by most other files) and apply uniformly.

---

## File: src/packages/colcraft/factors.ml
### Finding: fct_reorder_impl median calculation uses List.nth with fragile coupling (Original lines: 253, 258-259)
**Actual line**: 253, 258-259
**Status**: CONFIRMED (INFO)
**Evidence**: Line 253 guards against `data = []` with `neg_infinity`, so the median branches at lines 258-259 only execute when `len > 0`. The `List.nth sorted (len / 2 - 1)` at line 259 is safe only because the even-length branch requires `len >= 2`. The coupling between the guard and the median logic is implicit.
**Verdict**: The review correctly identifies fragile coupling. Not a bug in current code but could break if the guard is modified.
**Better fix** (optional): Extract a `median_of_sorted` helper that handles the empty case explicitly.
