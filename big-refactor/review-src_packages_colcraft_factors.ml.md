# Review: `src/packages/colcraft/factors.ml`

**Lines**: 957 (approx. 310 lines of code; remainder is `--#` docstring blocks)

**Severity summary**: 1 critical, 1 warning, 2 info

---

## CRITICAL: Unvalidated `x_arr.(i)` access in `fct_reorder_impl`

- **Line 244**: Inside `fct_reorder_impl`, the function accepts `[VVector f_arr; VVector x_arr]` but uses `n = Array.length f_arr` as the loop bound (line 240). The companion array `x_arr` is never checked for equal length. If `Array.length x_arr < Array.length f_arr`, accessing `x_arr.(i)` at line 244 raises `Invalid_argument "index out of bounds"` — a raw OCaml exception that is not caught, crashing the evaluator instead of returning a `VError`.

  **Fix**: Before the `for` loop (line 239), add:
  ```ocaml
  if Array.length f_arr <> Array.length x_arr then
    Error.value_error "Function `fct_reorder`: `.f` and `.x` must have the same length."
  ```
  and restructure the function to propagate the error (currently it returns `VVector` directly).

---

## WARNING: Unnecessary function alias `factor_impl`

- **Line 95**: `let factor_impl = to_factor_impl` creates a trivial alias. The name `to_factor_impl` is never used after this line except as the RHS of this binding; line 941 registers `factor_impl` (not `to_factor_impl`) as `"to_factor"`. This is dead code in the sense that the original name is unreferenced.

  **Fix**: Rename `to_factor_impl` directly to `factor_impl` and delete the alias at line 95. Alternatively, keep the better name and drop the alias.

---

## INFO: Inconsistent error message style

- Several functions use lowercase, no-`Function` prefix format (e.g. line 41: `"to_factor expects at least 1 argument"`, line 177: `"fct_rev expects 1 argument"`).
- Others use `"Function \`foo\` expects…"` (e.g. lines 458, 474, 518).
- `string_values_of` (line 448) takes `function_name` as a parameter and uses the `Function` style, while the direct `Error.make_error` calls inline the name.

  **Fix**: Pick one style — preferably `"Function \`foo\` expects…"` which is more helpful for debugging — and apply it consistently across all error messages in the file.

---

## INFO: `fct_reorder_impl` median calculation uses `List.nth` from a `data = []` guard

- **Lines 253, 258–259**: The function guards against `data = []` (line 253) with `neg_infinity`, so the median branches at lines 258–259 only execute when `len > 0`. The access `List.nth sorted (len / 2 - 1)` (line 259) is safe because the even-length branch only runs when `len >= 2`. Not a bug, but a fragile coupling — any future edit that changes the guard could silently introduce a crash.

  **Fix** (optional): Refactor to a helper `median_of_sorted` that returns `neg_infinity` for empty input, keeping the bounds logic encapsulated.
