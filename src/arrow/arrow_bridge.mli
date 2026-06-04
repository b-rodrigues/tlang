(* src/arrow/arrow_bridge.mli *)

open Ast

val column_to_values : Arrow_table.column_data -> value array

val value_at : Arrow_table.column_data -> int -> value

val values_to_column : value array -> Arrow_table.column_data

val row_to_dict : Arrow_table.t -> int -> (string * value) list

val table_from_value_columns : (string * value array) list -> int -> Arrow_table.t

val table_to_value_columns : Arrow_table.t -> (string * value array) list

val prepare_value_for_serialization : value -> value
