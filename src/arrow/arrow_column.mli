(* src/arrow/arrow_column.mli *)

open Bigarray

(** An opaque handle to a column view. References the backing table to prevent GC collection. *)
type column_view

type numeric_view =
  | FloatView of (float, float64_elt, c_layout) Array1.t
  | IntView of (int64, int64_elt, c_layout) Array1.t

val get_column : Arrow_table.t -> string -> column_view option

val column_type : column_view -> Arrow_table.arrow_type

val column_length : column_view -> int

val column_data : column_view -> Arrow_table.column_data

val zero_copy_view : column_view -> numeric_view option

(** Access a single element from a column view.
    This function is bounds-safe and returns [VNA NAGeneric] if the index is out of bounds. *)
val get_value_at : column_view -> int -> Ast.value

(** Create a slice (sub-view) of a column view.
    This function is bounds-safe and clamps start/len indices to prevent out-of-bounds exceptions. *)
val get_slice : column_view -> int -> int -> column_view

(** Convert a column view to a list of T-Lang runtime values.
    @deprecated This function has O(n) heap allocation cost and loses SIMD layout benefits. Avoid in hot paths. *)
val column_view_to_list : column_view -> Ast.value list
