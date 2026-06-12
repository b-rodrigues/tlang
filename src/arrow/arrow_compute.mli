(* src/arrow/arrow_compute.mli *)

(** Safe interface to Arrow-based computational kernels and grouping operations.
    
    Functions in this module return [option] values when columns are missing or
    have incompatible type layouts. Callers must handle [None] cases appropriately. *)

type grouped_handle

type grouped_table

type comparison_op = Eq | Lt | Gt | Le | Ge

val project : Arrow_table.t -> string list -> Arrow_table.t

val filter : Arrow_table.t -> bool array -> Arrow_table.t

val add_column : Arrow_table.t -> string -> Arrow_table.column_data -> Arrow_table.t

val take_rows : Arrow_table.t -> int list -> Arrow_table.t

val sort_by_indices : Arrow_table.t -> int array -> Arrow_table.t

val rename_columns : Arrow_table.t -> (string * string) list -> Arrow_table.t

(** Sort a table by the values of a column.
    Returns [None] if the column does not exist or sorting is unsupported for its type. *)
val sort_by_column : Arrow_table.t -> string -> bool -> Arrow_table.t option

val add_computed_column : Arrow_table.t -> string -> Arrow_table.column_data -> Arrow_table.t

(** Add a float scalar to every element of a numeric column.
    Returns [None] if the column is missing or is not numeric. *)
val add_scalar : Arrow_table.t -> string -> float -> Arrow_table.t option

(** Add an integer scalar to every element of a numeric column.
    Returns [None] if the column is missing or is not numeric. *)
val add_int_scalar : Arrow_table.t -> string -> int -> Arrow_table.t option

(** Multiply every element of a numeric column by a float scalar.
    Returns [None] if the column is missing or is not numeric. *)
val multiply_scalar : Arrow_table.t -> string -> float -> Arrow_table.t option

(** Multiply every element of a numeric column by an integer scalar.
    Returns [None] if the column is missing or is not numeric. *)
val multiply_int_scalar : Arrow_table.t -> string -> int -> Arrow_table.t option

(** Subtract a float scalar from every element of a numeric column.
    Returns [None] if the column is missing or is not numeric. *)
val subtract_scalar : Arrow_table.t -> string -> float -> Arrow_table.t option

(** Subtract an integer scalar from every element of a numeric column.
    Returns [None] if the column is missing or is not numeric. *)
val subtract_int_scalar : Arrow_table.t -> string -> int -> Arrow_table.t option

(** Divide every element of a numeric column by a float scalar.
    Returns [None] if the column is missing or is not numeric.
    
    Note: There is no [divide_int_scalar] because division in T-Lang always promotes
    integer values to float-pointing values to match standard statistical programming division semantics. *)
val divide_scalar : Arrow_table.t -> string -> float -> Arrow_table.t option

(** Add two columns element-wise.
    Returns [None] if either column is missing or their types are incompatible. *)
val add_columns_to_table : Arrow_table.t -> string -> string -> string -> Arrow_table.t option

(** Multiply two columns element-wise.
    Returns [None] if either column is missing or their types are incompatible. *)
val multiply_columns_to_table : Arrow_table.t -> string -> string -> string -> Arrow_table.t option

(** Subtract two columns element-wise.
    Returns [None] if either column is missing or their types are incompatible. *)
val subtract_columns_to_table : Arrow_table.t -> string -> string -> string -> Arrow_table.t option

(** Divide two columns element-wise.
    Returns [None] if either column is missing or their types are incompatible. *)
val divide_columns_to_table : Arrow_table.t -> string -> string -> string -> Arrow_table.t option

(** Group a table by key columns.
    Uses optimized native hash grouping when possible. *)
val group_by : Arrow_table.t -> string list -> grouped_table

(** Get groups of a grouped table.
    Each group is represented as a tuple of the string key representation and the list of row indices. *)
val get_groups : grouped_table -> (string * int list) list

val nest : grouped_table -> string list -> (string * Arrow_table.t) list

(** Apply an aggregation to a grouped table.
    agg_name: "sum", "mean", "count", "min", "max", or "count_distinct"
    col_name: target column for aggregation (ignored for count)
    Returns [Some table] with key columns + aggregated value column, or [None] if inputs are invalid. *)
val group_aggregate : grouped_table -> string -> string -> Arrow_table.t option

val group_multi_aggregate : grouped_table -> (string * string * string) list -> Arrow_table.t option

val sqrt_column : Arrow_table.t -> string -> Arrow_table.t option

val abs_column : Arrow_table.t -> string -> Arrow_table.t option

val log_column : Arrow_table.t -> string -> Arrow_table.t option

val exp_column : Arrow_table.t -> string -> Arrow_table.t option

val pow_column : Arrow_table.t -> string -> float -> Arrow_table.t option

val sum_column : Arrow_table.t -> string -> float option

val mean_column : Arrow_table.t -> string -> float option

val min_column : Arrow_table.t -> string -> float option

val max_column : Arrow_table.t -> string -> float option

(** Compute the number of distinct values in a named column.
    Returns [None] if the column doesn't exist. *)
val count_distinct_column : Arrow_table.t -> string -> int option

(** Compare each element of a named numeric column to a scalar.
    Returns a bool array suitable for use with filter, or [None] if the column is missing/incompatible. *)
val compare_column_scalar : Arrow_table.t -> string -> float -> comparison_op -> bool array option

val column_null_mask : Arrow_table.t -> string -> bool array option

val dense_rank_column : Arrow_table.t -> string -> int option array option

val row_number_column : Arrow_table.t -> string -> int option array option

val min_rank_column : Arrow_table.t -> string -> int option array option

val lag_column : Arrow_table.t -> string -> int -> Arrow_table.t option

val lead_column : Arrow_table.t -> string -> int -> Arrow_table.t option
