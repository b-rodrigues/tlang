# Verification Report: src/arrow/arrow_compute.ml

## File: src/arrow/arrow_compute.ml

### Finding: Function too long — `group_aggregate_ocaml` (Original lines: 512-619)

**Actual lines**: 512-619 (108 lines)
**Status**: CONFIRMED

**Evidence**: The function spans lines 512-619 and handles all aggregation types (sum, mean, count, min, max, count_distinct) with deeply nested per-aggregation logic.

**Verdict**: Exceeds 80-line guideline. Per-aggregation extraction would improve readability and testability.

---

### Finding: `Hashtbl.find` without guard (Original line: 414)

**Actual line**: 414
**Status**: CONFIRMED

**Evidence**:
```
413:   let groups = List.rev_map (fun k ->
414:     (k, List.rev (Hashtbl.find group_map k))
415:   ) !group_order in
```
**Verdict**: `Hashtbl.find` raises `Not_found` if the key is absent. Meanwhile line 407 uses `try Hashtbl.find group_map key_str with Not_found -> []` for the same hashtbl. Inconsistent defensive programming — future refactors to `group_order` construction could introduce a mismatch crash.

---

### Finding: Unvalidated `List.hd` pattern on group indices (Original lines: 430-431)

**Actual lines**: 430-431 (with guards at 440-441)
**Status**: CONFIRMED (but review inaccurately claims "no runtime guard")

**Evidence**:
```
429:   let sorted_groups = List.sort (fun (_, indices_a) (_, indices_b) ->
430:     match indices_a, indices_b with
431:     | (a_first :: _, b_first :: _) ->
...
439:       cmp key_col_values
440:     | ([], _) -> -1
441:     | (_, []) -> 1
442:   ) groups in
```
**Verdict**: The review claims "there is no runtime guard", but empty lists ARE handled at lines 440-441. However, the review is correct that the fallback values `[-1]` and `[1]` are arbitrary sorting fallbacks that could produce surprising ordering if empty groups ever occur. The core concern (fragile assumption about non-empty groups) is valid, but the claim that there is no guard is inaccurate.

---

### Finding: Unvalidated `List.hd` pattern on group indices (Original line: 543)

**Actual line**: 543-544
**Status**: FALSE_POSITIVE

**Evidence**:
```
541:         let col = Array.init n_groups (fun g_idx ->
542:           let (_, indices) = groups_array.(g_idx) in
543:           match indices with
544:           | first :: _ -> key_vals.(first)
545:           | [] -> empty_na
546:         ) in
```
**Verdict**: The review claims "same assumption — every group has at least one index" and proposes "Add a defensive fallback (| [] -> empty_na)". But the defensive fallback `| [] -> empty_na` already exists on line 545. This finding is a complete false positive — the code already handles empty groups exactly as the review suggests.

---

### Finding: `column_binary_op` silently truncates (Original line: 213)

**Actual line**: 213
**Status**: CONFIRMED

**Evidence**:
```
211:   match Arrow_table.get_column t col1, Arrow_table.get_column t col2 with
212:   | Some (Arrow_table.FloatColumn a1), Some (Arrow_table.FloatColumn a2) ->
213:     let n = min (Array.length a1) (Array.length a2) in
```
**Verdict**: Exact match. Uses `min` which silently truncates to the shorter column. A length mismatch between columns (which shouldn't happen in well-formed tables) would be silently ignored rather than reported.

---

### Finding: Unnecessary `rec` keyword (Original lines: 372-443)

**Actual lines**: 372-443
**Status**: CONFIRMED (but partially inaccurate)

**Evidence**:
```
372: let rec group_by_standard (t : Arrow_table.t) (keys : string list) : grouped_table =
...
388: and group_by_ocaml (t : Arrow_table.t) (keys : string list) : grouped_table =
...
394: and build_ocaml_groups (t : Arrow_table.t) (keys : string list) : (string * int list) list =
```
**Verdict**: `group_by_standard` calls `group_by_ocaml` (line 383), but `group_by_ocaml` does not call `group_by_standard`. `build_ocaml_groups` is called by `group_by_ocaml` (line 389) but doesn't call either back. This is "forward reference", not "mutual recursion". The `rec` enables `group_by_standard` to see `group_by_ocaml` which is defined later. The finding is correct but the `rec` here is a pragmatic choice for readability (conceptual grouping) rather than a true defect.

---

### Finding: Unnecessary `rec` keyword (Original lines: 488-619)

**Actual lines**: 488-619
**Status**: CONFIRMED (same pattern as above)

**Evidence**:
```
488: let rec group_aggregate (grouped : grouped_table) (agg_name : string) (col_name : string) : Arrow_table.t option =
...
512: and group_aggregate_ocaml (grouped : grouped_table) (agg_name : string) (col_name : string) : Arrow_table.t option =
```
**Verdict**: `group_aggregate` calls `group_aggregate_ocaml` (line 507), but not vice versa. Forward reference, not mutual recursion. Same pragmatic assessment as above.

---

### Finding: `ref` mutability in OCaml fallback aggregations (Original lines: 571-579, 588-599, 602-614)

**Actual lines**: 571-579, 588-599, 602-614
**Status**: CONFIRMED (review slightly misidentifies lines)

**Evidence**:
- Lines 570-579 (mean): uses `ref sum` and `ref count` — actual `mean` aggregation, not `sum`
- Lines 587-600 (min): uses `ref m`
- Lines 601-614 (max): uses `ref m`

**Verdict**: The review says "sum, min, max aggregations" but references lines 571-579 which is actually the `mean` aggregation. The `sum` aggregation (lines 562-568) correctly uses `List.fold_left` without refs. The core finding (unnecessary ref usage) is valid for `mean`, `min`, and `max`.

---

### Finding: `native_fn` result discarded in OCaml fallback path (Original lines: 728-729)

**Actual lines**: 728-729
**Status**: CONFIRMED

**Evidence**:
```
728:     (match native_fn handle.ptr col_name with
729:      | Some _ as result -> result
730:      | None -> None)
```
**Verdict**: Exact match. The pattern `Some _ as result -> result` discards the bound value. Functionally correct (the value doesn't need to be inspected), but `Some v -> Some v` would be semantically clearer.
