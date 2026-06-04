(* src/arrow/arrow_compute.mli *)

type grouped_handle = {
  ptr : nativeint;
  mutable freed : bool;
}

type grouped_table = {
  base_table : Arrow_table.t;
  group_keys : string list;
  native_group : grouped_handle option;
  ocaml_groups : ((string * int list) list) option ref;
}

val project : Arrow_table.t -> string list -> Arrow_table.t

val filter : Arrow_table.t -> bool array -> Arrow_table.t

val add_column : Arrow_table.t -> string -> Arrow_table.column_data -> Arrow_table.t

val take_rows : Arrow_table.t -> int list -> Arrow_table.t

val sort_by_indices : Arrow_table.t -> int array -> Arrow_table.t

val rename_columns : Arrow_table.t -> (string * string) list -> Arrow_table.t

val sort_by_column : Arrow_table.t -> string -> bool -> Arrow_table.t option

val add_computed_column : Arrow_table.t -> string -> Arrow_table.column_data -> Arrow_table.t

val add_scalar : Arrow_table.t -> string -> float -> Arrow_table.t option

val add_int_scalar : Arrow_table.t -> string -> int -> Arrow_table.t option

val multiply_scalar : Arrow_table.t -> string -> float -> Arrow_table.t option

val multiply_int_scalar : Arrow_table.t -> string -> int -> Arrow_table.t option

val subtract_scalar : Arrow_table.t -> string -> float -> Arrow_table.t option

val subtract_int_scalar : Arrow_table.t -> string -> int -> Arrow_table.t option

val divide_scalar : Arrow_table.t -> string -> float -> Arrow_table.t option

val add_columns_to_table : Arrow_table.t -> string -> string -> string -> Arrow_table.t option

val multiply_columns_to_table : Arrow_table.t -> string -> string -> string -> Arrow_table.t option

val subtract_columns_to_table : Arrow_table.t -> string -> string -> string -> Arrow_table.t option

val divide_columns_to_table : Arrow_table.t -> string -> string -> string -> Arrow_table.t option

val group_by : Arrow_table.t -> string list -> grouped_table

val group_by_optimized : Arrow_table.t -> string list -> grouped_table

val get_ocaml_groups : grouped_table -> (string * int list) list

val nest : grouped_table -> string list -> (string * Arrow_table.t) list

val ocaml_groups_materialized : grouped_table -> bool

val group_aggregate : grouped_table -> string -> string -> Arrow_table.t

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

val count_distinct_column : Arrow_table.t -> string -> float option

val compare_column_scalar : Arrow_table.t -> string -> float -> string -> bool array option

val column_null_mask : Arrow_table.t -> string -> bool array option

val dense_rank_column : Arrow_table.t -> string -> int option array option

val row_number_column : Arrow_table.t -> string -> int option array option

val min_rank_column : Arrow_table.t -> string -> int option array option

val lag_column : Arrow_table.t -> string -> int -> Arrow_table.t option

val lead_column : Arrow_table.t -> string -> int -> Arrow_table.t option
