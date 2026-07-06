# Review: src/arrow/arrow_compute.ml

**Lines**: 932
**Severity summary**: 0 critical, 3 warning, 4 info

---

## WARNING: Function too long — `group_aggregate_ocaml`

- **Lines 512-619** (108 lines): `group_aggregate_ocaml` handles all aggregation types (sum, mean, count, min, max, count_distinct) in a single monolithic function with deeply nested matches and per-aggregation logic inline.

  **Fix**: Extract per-aggregation functions (e.g., `aggregate_sum`, `aggregate_mean`, `aggregate_min`, `aggregate_max`) and compose them from `group_aggregate_ocaml`. This would also make the per-agg logic independently testable.

---

## WARNING: `Hashtbl.find` without guard

- **Line 414**: `Hashtbl.find group_map k`

  In `build_ocaml_groups`, the key `k` comes from `!group_order` which is built from keys inserted into the map, so it should always succeed. However, other code paths (line 407) use `try ... with Not_found -> ...` for the same operation. This inconsistency is fragile: a future change to group construction could introduce a mismatch.

  **Fix**: Use `Hashtbl.find_opt` with a fallback (`[]`), or use the same `try/with` pattern as line 407 for consistency.

---

## WARNING: Unvalidated `List.hd` pattern on group indices

- **Lines 430-431**: `| (a_first :: _, b_first :: _) ->`

  In `build_ocaml_groups` group sorting. The pattern assumes every group has at least one index. While this is true by construction (every group key is created with at least one `i :: existing`), there is no runtime guard.

- **Line 543**: `| first :: _ -> key_vals.(first)`

  In `group_aggregate_ocaml`, same assumption — every group has at least one index.

  **Fix**: Add a defensive fallback (`| [] -> 0` for sorting, `| [] -> empty_na` for aggregation) to handle empty groups gracefully if the invariant is ever violated.

---

## INFO: `column_binary_op` silently truncates to shorter column length

- **Line 213**: `let n = min (Array.length a1) (Array.length a2) in`

  If two columns have different lengths (which should not happen in a well-formed table), extra elements are silently ignored. The mismatch may indicate a corruption bug upstream.

  **Fix**: Assert or validate equal column lengths, or log a warning when lengths differ.

---

## INFO: Unnecessary `rec` keyword on non-recursive function groups

- **Lines 372-443**: `group_by_standard`, `group_by_ocaml`, `build_ocaml_groups` are declared as `let rec ... and ... and ...` but are not mutually recursive.

- **Lines 488-619**: `group_aggregate` and `group_aggregate_ocaml` are declared as `let rec ... and ...` but are not mutually recursive.

  **Fix**: Use separate `let` bindings without `rec` for clarity.

---

## INFO: OCaml fallback aggregations use `ref` mutability

- **Lines 571-579, 588-599, 602-614**: `sum`, `min`, `max` aggregations in `group_aggregate_ocaml` use local `ref` cells with imperative `List.iter`. While functionally correct and performant, `List.fold` would be more idiomatic for sum and count.

  **Fix**: Use `List.fold_left` for sum/count accumulations to avoid mutable state.

---

## INFO: `native_fn` result discarded in OCaml fallback path

- **Lines 728-729**: `| Some _ as result -> result` / `| None -> None`

  In `column_agg`, the native path returns `Some _` but the value is discarded and returned as-is. This is correct (the native function already computed the aggregation), but the `Some _` pattern could be `Some v -> Some v` for clarity.

  **Fix**: Use `| Some v -> Some v` to make it explicit that the value is passed through.
