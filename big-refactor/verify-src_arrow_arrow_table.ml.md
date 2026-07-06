# Verification Report: src/arrow/arrow_table.ml

## File: src/arrow/arrow_table.ml

### Finding: `invalid_arg` raises raw OCaml exceptions (Original line: 581)

**Actual line**: 581
**Status**: CONFIRMED

**Evidence**:
```
580:                      if Array.length indices <> sub_t.nrows then
581:                        invalid_arg ("ArrowDictionary flatten: invalid index array length for field " ^ fname);
```
**Verdict**: Exact match. `invalid_arg` raises a raw OCaml exception from `flatten_list_column`, called from `materialize`. The catch-all at line 701 does catch it, but the function itself should not rely on callers to handle exceptions.

---

### Finding: `invalid_arg` inconsistent dictionary payloads (Original line: 588)

**Actual line**: 588
**Status**: CONFIRMED

**Evidence**:
```
587:                           if expected_ordered <> ord || not (validate_levels expected_levels lvl) then
588:                             invalid_arg ("ArrowDictionary flatten: incompatible dictionary payloads for field " ^ fname)
```
**Verdict**: Exact match.

---

### Finding: `invalid_arg` inconsistent metadata state (Original line: 590)

**Actual line**: 590
**Status**: CONFIRMED

**Evidence**:
```
589:                       | _ ->
590:                           invalid_arg ("ArrowDictionary flatten: inconsistent dictionary metadata state for field " ^ fname));
```
**Verdict**: Exact match.

---

### Finding: `invalid_arg` out-of-bounds dictionary index (Original line: 595)

**Actual line**: 595
**Status**: CONFIRMED

**Evidence**:
```
594:                         | Some idx when idx < 0 || idx >= level_count ->
595:                             invalid_arg ("ArrowDictionary flatten: out-of-bounds dictionary index for field " ^ fname)
```
**Verdict**: Exact match.

---

### Finding: `assert` in user-facing code (Original line: 837)

**Actual line**: 837
**Status**: CONFIRMED

**Evidence**:
```
837:   assert (!j = new_nrows); (* Invariant: mask true-count must match new_nrows *)
```
**Verdict**: Exact match. `assert` raises `Assert_failure` if the invariant is violated.

---

### Finding: `Option.get` without pattern matching (Original line: 395)

**Actual line**: 395
**Status**: CONFIRMED

**Evidence**:
```
394:        if all_native && Arrow_ffi.arrow_available then
395:          let ptrs = List.map (fun t -> (Option.get t.native_handle).ptr) tables in
```
**Verdict**: Exact match. The guard `all_native` ensures all handles are `Some`, but `Option.get` is fragile against future refactors.

---

### Finding: Function too long — `flatten_list_column` (Original lines: 525-623)

**Actual lines**: 525-623 (99 lines)
**Status**: CONFIRMED

**Evidence**: The function spans lines 525-623 with deeply nested dictionary flattening logic (lines 568-602), generic sub-column flattening, and multiple `invalid_arg` calls.

**Verdict**: Exceeds the 80-line guideline.

---

### Finding: Catch-all exception handler (Original lines: 701-705)

**Actual lines**: 700-705
**Status**: CONFIRMED

**Evidence**:
```
700:         | Out_of_memory | Stack_overflow as exn -> raise exn
701:         | exn ->
702:             Printf.eprintf
703:               "Warning: Native materialization failed (%s). Keeping OCaml representation.\n%!"
704:               (Printexc.to_string exn);
705:             t
```
**Verdict**: Intentional design (native materialization is best-effort), but the catch-all silently swallows unexpected exceptions like `null` pointer dereferences. The review notes the exact lines but clarifies the first catch line is 700, with 701-705 being the catch-all.

---

### Finding: Mutable module-level state (Original lines: 39-42)

**Actual lines**: 39-42
**Status**: CONFIRMED

**Evidence**:
```
39: let zero_copy_events : zero_copy_event list ref = ref []
40: let zero_copy_event_count : int ref = ref 0
41: let max_zero_copy_events = 1000
42: let zero_copy_cap_warned : bool ref = ref false
```
**Verdict**: Exact match. Mutable module-level `ref` cells, non-thread-safe. The review correctly notes this is guarded by `env_flag "TLANG_ZERO_COPY_DEBUG"` but still fragile in concurrent contexts.

---

### Finding: `raise Exit` for control flow (Original lines: 279-291)

**Actual lines**: 279-280, 291 (the `raise Exit` is on line 280, caught on line 291)
**Status**: CONFIRMED

**Evidence**:
```
279:                 if offset < 0 || len < 0 || offset + len > max_len then
280:                   raise Exit
...
291:         with Exit -> None
```
**Verdict**: The review says "lines 279-291" which describes the broader `try/with` block. The `raise Exit` is on line 280 and the catch is on line 291. Pattern is fragile — if new code is added between the `try` and the `raise Exit`, the exception could be accidentally caught by a different handler.

---

### Finding: Unnecessary `let rec` for non-recursive functions (Original lines: 383, 404)

**Actual lines**: 383, 404
**Status**: CONFIRMED

**Evidence**:
```
383: let rec concatenate (tables : t list) : t =
...
404: and concatenate_ocaml (tables : t list) : t =
```
**Verdict**: Exact match. `concatenate` calls `concatenate_ocaml` (line 400), but `concatenate_ocaml` does not call `concatenate`. Not mutually recursive. `rec` is unnecessary if the functions are reordered or declared separately.
