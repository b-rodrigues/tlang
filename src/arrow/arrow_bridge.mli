(* src/arrow/arrow_bridge.mli *)

(** Conversion bridge between Arrow columnar storage and T-Lang value representation (Ast.value).
    
    Warning: Operations in this module generally involve heap allocations and memory copies.
    Prefer zero-copy views in Arrow_column for hot paths. *)

open Ast

type row_count = int

(** Convert an entire Arrow column data to an array of T-Lang values.
    Costly memory copy and allocation: O(n). *)
val column_to_values : Arrow_table.column_data -> value array

(** Extract a single value from an Arrow column at the specified row index.
    This function is bounds-safe and returns the appropriate type-specific NA value
    (e.g., VNA NAInt for IntColumn) if the index is out of bounds. *)
val value_at : Arrow_table.column_data -> int -> value

val values_to_column : value array -> Arrow_table.column_data

(** Extract a specific row from an Arrow table as an associative dictionary of field names to values.
    This function is bounds-safe and returns VNA NAGeneric values if the index is out of bounds. *)
val row_to_dict : Arrow_table.t -> int -> (string * value) list

(** Create an Arrow table from T-Lang value column structures.
    Validates that all column arrays match the specified [row_count], raising Invalid_argument if not. *)
val table_from_value_columns : (string * value array) list -> row_count -> Arrow_table.t

(** Convert an Arrow table structure back to T-Lang value column arrays.
    Costly memory copy and allocation. *)
val table_to_value_columns : Arrow_table.t -> (string * value array) list

(** Recursively prepare a T-Lang value for safe serialization by cleansing native memory pointers
    (such as native Arrow table pointers) to prevent use-after-free and serialization of invalid memory addresses. *)
val prepare_value_for_serialization : value -> value
