(* src/arrow/arrow_compute.ml *)
(* Arrow Compute operations for T's colcraft verbs.                      *)
(* Provides project, filter, sort, and column manipulation.              *)
(* When Arrow C GLib is available, these will delegate to Arrow Compute  *)
(* kernels for zero-copy operations and SIMD acceleration.               *)

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
