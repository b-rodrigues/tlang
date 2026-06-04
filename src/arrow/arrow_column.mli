(* src/arrow/arrow_column.mli *)

open Bigarray

type column_view = {
  backing : Arrow_table.t;
  column_name : string;
  data : Arrow_table.column_data;
}

type numeric_view =
  | FloatView of (float, float64_elt, c_layout) Array1.t
  | IntView of (int64, int64_elt, c_layout) Array1.t

val get_column : Arrow_table.t -> string -> column_view option

val column_type : column_view -> Arrow_table.arrow_type

val column_length : column_view -> int

val column_data : column_view -> Arrow_table.column_data

val zero_copy_view : column_view -> numeric_view option

val get_value_at : column_view -> int -> Ast.value

val get_slice : column_view -> int -> int -> column_view

val column_view_to_list : column_view -> Ast.value list
