# Review: src/packages/core/t_boolean.ml

**Lines**: 471
**Severity summary**: 2 critical, 1 warning, 1 info

---

## CRITICAL: Unvalidated List.nth on potentially-empty list

- **Line 403**: `snd (List.nth l 0)` in `get_rep_value` — if `l` is `[]` (empty list), `List.nth l 0` raises `Failure "nth"`. The function `get_rep_value` is called for each potential value, and `VList []` is a valid T value.

  **Fix**: Use `List.nth_opt` instead:
  ```ocaml
  match List.nth_opt l 0 with
  | Some (_, v) -> v
  | None -> (VNA NAGeneric)
  ```

- **Line 404**: Same pattern `snd (List.nth l 0)` in the same function, same issue.

  **Fix**: Same as above.

## WARNING: Deeply nested match expressions

- **Lines 82–161**: The `ifelse` function has nested match/case blocks 8 levels deep. While each level handles a distinct validation concern (positional args, named args, missing/out_type dedup, length, type inference, cast), the nesting makes the control flow hard to follow and increases the risk of missing a case.

  **Fix**: Extract helper functions for argument parsing, type normalization, and result construction.

## INFO: Array indexing with i mod n for recycling

- **Lines 120, 124, 127**: `arr.(i mod n)` correctly handles recycling (R-style vector recycling). The `n = 0` guard before these lines prevents division-by-zero or bounds errors.

  **Fix**: No change needed.
