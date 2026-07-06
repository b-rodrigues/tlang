# Review: src/arrow/arrow_column.ml

**Lines**: 146
**Severity summary**: 0 critical, 0 warning, 1 info

---

No issues found. The file is well-structured:

- All array accesses (`a.(idx)`) are guarded by explicit bounds checks (`get_value_at` line 88).
- `Array.sub` calls in `get_slice` (lines 121–137) are protected by clamping on lines 117–118 that ensures `start + len ≤ total`.
- No `raise`, `failwith`, `assert false`, or `Option.get`.
- No `List.hd` / `List.tl` / `Hashtbl.find` without guard.
- All functions are under 30 lines.
- `zero_copy_view` correctly checks `handle.Arrow_table.freed` before using the native pointer.

## INFO: `Sys.opaque_identity` used to prevent GC of backing table

- **Lines 65, 74**: `ignore (Sys.opaque_identity col.backing)` is used to keep the backing table alive while a zero-copy Bigarray view is active. This is a well-known OCaml FFI pattern but is fragile — the optimizer could theoretically eliminate the reference. If the backing table is freed, the Bigarray points to garbage memory.

  **Fix**: This is an accepted trade-off for zero-copy Arrow interop. No change needed, but consider adding a comment explaining why the backing table reference must be retained for the lifetime of the Bigarray.
