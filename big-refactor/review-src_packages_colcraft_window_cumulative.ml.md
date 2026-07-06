# Review: src/packages/colcraft/window_cumulative.ml

**Lines**: 340
**Severity summary**: 0 critical, 0 warnings, 1 info

---

## INFO: Inefficient backfill loop in cumsum/cummin/cummax

- **Lines 54–59, 113–117, 171–175**: When a `VFloat` value is encountered after `VInt` values in cumsum/cummin/cummax, the code backfills all previous `VInt` results to `VFloat`:
  ```
  for j = 0 to i - 1 do
    match result.(j) with
    | VInt v -> result.(j) <- VFloat (float_of_int v)
    | _ -> ()
  done;
  ```
  This is O(n²) worst-case (e.g., alternating int/float). The same backfill pattern appears identically in all three functions.

  **Fix**: Track whether a type conversion has already been performed with a boolean flag (`already_converted`) instead of re-scanning from index 0 on every float encounter. This reduces to O(n).

---

No critical issues or warnings found. All match expressions are exhaustive. No unsafe `Option.get`, `List.hd`, `Hashtbl.find` (without opt), or uncaught exceptions. `to_value_array` correctly propagates errors via `Result`. NA propagation is handled explicitly.
