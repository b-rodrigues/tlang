# Review: src/arrow/arrow_table.ml

**Lines**: 1035
**Severity summary**: 4 critical, 5 warning, 2 info

---

## CRITICAL: `invalid_arg` raises raw OCaml exceptions on user-facing path

- **Line 581**: `invalid_arg ("ArrowDictionary flatten: invalid index array length for field " ^ fname)`

  Called from `flatten_list_column` which is called from `materialize`. Although `materialize` has a catch-all at line 701 that catches this and degrades gracefully, the function itself should return `VError` or use `Option`/`Result` instead of raising.

  **Fix**: Replace `invalid_arg` with an `Error.value_error` return or propagate via `Option`/`Result` type.

- **Line 588**: `invalid_arg ("ArrowDictionary flatten: incompatible dictionary payloads for field " ^ fname)`

  Same issue as above — raises on incompatible dictionary levels/ordering across sub-tables.

  **Fix**: Same as above.

- **Line 590**: `invalid_arg ("ArrowDictionary flatten: inconsistent dictionary metadata state for field " ^ fname)`

  Same pattern — `levels` and `ordered` refs should never be in inconsistent state (one Some, one None), but raises rather than returning an error.

  **Fix**: Same as above.

- **Line 595**: `invalid_arg ("ArrowDictionary flatten: out-of-bounds dictionary index for field " ^ fname)`

  Raises on out-of-bounds dictionary index. Should return an error value instead.

  **Fix**: Same as above.

---

## CRITICAL: `assert` in user-facing code

- **Line 837**: `assert (!j = new_nrows)`

  In `_filter_column_pure`. `assert` raises `Assert_failure` if the invariant is violated (mask true-count does not match new_nrows). This is a programmer-error check, but per code safety rules, user-facing code paths must not raise raw OCaml exceptions.

  **Fix**: Replace with a conditional that returns a safe fallback or propagates an error.

---

## WARNING: `Option.get` with prior validation (fragile)

- **Line 395**: `(Option.get t.native_handle).ptr`

  Used inside the `all_native` branch which guarantees all handles are `Some`, but uses `Option.get` rather than pattern matching. A future refactor that weakens the guard would introduce a runtime crash.

  **Fix**: Replace with `match t.native_handle with Some h -> h.ptr | None -> ...` (or use `List.filter_map` to extract ptrs directly).

---

## WARNING: Function too long — `flatten_list_column`

- **Lines 525-623** (99 lines): `flatten_list_column` handles dictionary flattening, generic column concatenation, and list-of-struct sub-column flattening in a single function. The dictionary branch alone (lines 569–602) is deeply nested and contains multiple `invalid_arg` paths.

  **Fix**: Extract the dictionary-column flattening logic into a helper function (`flatten_dictionary_sub_column`). Consider extracting the generic sub-column flattening (lines 603–619) into another helper.

---

## WARNING: Catch-all exception handler

- **Lines 701-705**: `| exn -> Printf.eprintf "Warning: ..."`

  `materialize` catches all exceptions (except `Out_of_memory` and `Stack_overflow`) and silently degrades to pure OCaml. While intentional, this pattern hides bugs — an unexpected error (e.g., a null pointer dereference in the FFI) would be silently swallowed.

  **Fix**: Log the full exception with a backtrace, or only catch specific known exception types from the FFI calls.

---

## WARNING: Mutable module-level state

- **Lines 39-42**: `zero_copy_events`, `zero_copy_event_count`, `max_zero_copy_events`, `zero_copy_cap_warned`

  Mutable `ref` cells at module scope. While documented and guarded by `TLANG_ZERO_COPY_DEBUG`, mutable module state is non-thread-safe and can cause surprising behavior if the module is used in a concurrent context.

  **Fix**: Either document the thread-safety limitation explicitly, or encapsulate in a record passed through the call chain.

---

## INFO: `raise Exit` for control flow

- **Lines 279-291**: `raise Exit` / `with Exit -> None`

  Used in `read_native_list_column_from_ptr` as a non-local early-exit mechanism when offset bounds are invalid. This is a legitimate OCaml pattern but fragile — if a new code path is added between the `try` and `raise Exit`, it could be accidentally caught.

  **Fix**: Use an explicit `Option` return type and `match`/`let*` instead of exceptions for control flow.

---

## INFO: Unnecessary `let rec ... and ...` for non-recursive functions

- **Lines 383, 404**: `concatenate` and `concatenate_ocaml` are declared as `let rec ... and ...` but are not mutually recursive (`concatenate` calls `concatenate_ocaml` but not vice versa).

  **Fix**: Remove the `rec` keyword and use separate `let` bindings.
