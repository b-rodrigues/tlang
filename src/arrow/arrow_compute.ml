(* src/arrow/arrow_compute.ml *)
(* Arrow Compute operations for T's colcraft verbs.                      *)
(* When a table has a native_handle, delegates to Arrow Compute kernels  *)
(* via FFI for zero-copy operations and SIMD acceleration.               *)
(* Falls back to pure OCaml implementations when no native handle.       *)

(** Project (select) columns by name — delegates to Arrow_table.project *)
let project = Arrow_table.project

(** Filter rows using a boolean mask — delegates to Arrow_table.filter_rows *)
let filter = Arrow_table.filter_rows

(** Add or replace a column — delegates to Arrow_table.add_column *)
let add_column = Arrow_table.add_column

(** Take rows by index list — delegates to Arrow_table.take_rows *)
let take_rows = Arrow_table.take_rows

(** Sort table by indices — delegates to Arrow_table.sort_by_indices *)
let sort_by_indices = Arrow_table.sort_by_indices

(** Sort table by column name using native Arrow sort when available.
    Returns a new table sorted by the given column. *)
let sort_by_column (t : Arrow_table.t) (col_name : string) (ascending : bool) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_table_sort handle.ptr col_name ascending with
       | Some new_ptr ->
           Some (Arrow_table.create_from_native new_ptr t.schema t.nrows)
       | None -> None)
  | _ -> None
