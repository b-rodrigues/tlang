(* src/arrow/arrow_ffi.mli *)

(** Low-level C FFI bindings for the native Arrow backend.

    {b Warning:} Prefer {!Arrow_compute} and {!Arrow_column} for all application code.
    Direct use of this module requires manual lifetime management of [nativeint] handles.
    Passing a handle after it has been freed, or passing a handle of the wrong type,
    will result in a native crash or undefined behavior that OCaml cannot catch.

    This module is exposed so that [Arrow_compute] and [Arrow_io] can depend on it
    as a library boundary. It is not part of the stable public API. *)

val arrow_available : bool

external arrow_table_free : nativeint -> unit
  = "caml_arrow_table_free"

external arrow_table_num_rows : nativeint -> int
  = "caml_arrow_table_num_rows"

external arrow_table_num_columns : nativeint -> int
  = "caml_arrow_table_num_columns"

external arrow_table_get_schema : nativeint -> (string * int * string option) list
  = "caml_arrow_table_get_schema"

external arrow_table_get_list_field_schema : nativeint -> string -> (string * int * string option) list option
  = "caml_arrow_table_get_list_field_schema"

external arrow_table_get_column_data : nativeint -> string -> nativeint option
  = "caml_arrow_table_get_column_data_by_name"

external arrow_read_int64_column : nativeint -> int option array
  = "caml_arrow_read_int64_column"

external arrow_read_float64_column : nativeint -> float option array
  = "caml_arrow_read_float64_column"

external arrow_read_boolean_column : nativeint -> bool option array
  = "caml_arrow_read_boolean_column"

external arrow_read_string_column : nativeint -> string option array
  = "caml_arrow_read_string_column"

external arrow_read_date32_column : nativeint -> int option array
  = "caml_arrow_read_date32_column"

external arrow_read_timestamp_column : nativeint -> int64 option array
  = "caml_arrow_read_timestamp_column"

external arrow_read_dictionary_column : nativeint -> (int option array * string list * bool)
  = "caml_arrow_read_dictionary_column"

external arrow_read_list_column : nativeint -> (nativeint option * (int * int) option array)
  = "caml_arrow_read_list_column"

external arrow_read_struct_fields : nativeint -> (string * int * string option) list
  = "caml_arrow_read_struct_fields"

external arrow_read_struct_field : nativeint -> int -> nativeint option
  = "caml_arrow_read_struct_field"

external arrow_unref : nativeint -> unit
  = "caml_arrow_unref"

external arrow_read_csv : string -> nativeint option
  = "caml_arrow_read_csv"

external arrow_read_parquet : string -> nativeint option
  = "caml_arrow_read_parquet"

external arrow_read_ipc : string -> nativeint option
  = "caml_arrow_read_ipc"

external arrow_write_ipc : nativeint -> string -> bool
  = "caml_arrow_write_ipc"

external arrow_table_project : nativeint -> string list -> nativeint option
  = "caml_arrow_table_project"

external arrow_table_filter_mask : nativeint -> bool array -> nativeint option
  = "caml_arrow_table_filter_mask"

external arrow_table_remove_column : nativeint -> string -> nativeint option
  = "caml_arrow_table_remove_column"

external arrow_table_rename_column : nativeint -> string -> string -> nativeint option
  = "caml_arrow_table_rename_column"

external arrow_table_add_column_from_table : nativeint -> string -> nativeint -> string -> nativeint option
  = "caml_arrow_table_add_column_from_table"

external arrow_table_slice : nativeint -> int64 -> int64 -> nativeint option
  = "caml_arrow_table_slice"

external arrow_table_take : nativeint -> int array -> nativeint option
  = "caml_arrow_table_take"

external arrow_table_sort : nativeint -> string -> bool -> nativeint option
  = "caml_arrow_table_sort"

(** Construct a new Arrow table from OCaml column data.

    {b Warning:} The ['a array] type parameter is polymorphic only to satisfy the OCaml
    type-checker at the FFI boundary. The C implementation casts this to a typed Arrow
    array and will produce undefined behavior if the wrong element type is passed.
    Callers must ensure the array element type is consistent with the [int] type tag
    in the tuple [(name, type_tag, nullable, data)]. Use {!Arrow_compute.add_computed_column}
    instead of calling this directly. *)
external arrow_table_new : (string * int * string option * 'a array) list -> nativeint option
  = "caml_arrow_table_new"

external arrow_table_concatenate : nativeint list -> nativeint option
  = "caml_arrow_table_concatenate"

external arrow_compute_add_scalar : nativeint -> string -> float -> nativeint option
  = "caml_arrow_compute_add_scalar"

external arrow_compute_multiply_scalar : nativeint -> string -> float -> nativeint option
  = "caml_arrow_compute_multiply_scalar"

external arrow_compute_subtract_scalar : nativeint -> string -> float -> nativeint option
  = "caml_arrow_compute_subtract_scalar"

external arrow_compute_divide_scalar : nativeint -> string -> float -> nativeint option
  = "caml_arrow_compute_divide_scalar"

external arrow_compute_add_columns : nativeint -> string -> string -> string -> nativeint option
  = "caml_arrow_compute_add_columns"

external arrow_compute_multiply_columns : nativeint -> string -> string -> string -> nativeint option
  = "caml_arrow_compute_multiply_columns"

external arrow_compute_subtract_columns : nativeint -> string -> string -> string -> nativeint option
  = "caml_arrow_compute_subtract_columns"

external arrow_compute_divide_columns : nativeint -> string -> string -> string -> nativeint option
  = "caml_arrow_compute_divide_columns"

external arrow_table_group_by : nativeint -> string list -> nativeint option
  = "caml_arrow_table_group_by"

external arrow_grouped_table_free : nativeint -> unit
  = "caml_arrow_grouped_table_free"

external arrow_table_merge_horizontal : nativeint -> nativeint -> nativeint option
  = "caml_arrow_table_merge_horizontal"

external arrow_grouped_table_get_indices : nativeint -> (string * int list) list
  = "caml_arrow_grouped_table_get_indices"

external arrow_grouped_table_nest : nativeint -> (string * nativeint) list
  = "caml_arrow_grouped_table_nest"

external arrow_group_sum : nativeint -> string -> nativeint option
  = "caml_arrow_group_sum"

external arrow_group_mean : nativeint -> string -> nativeint option
  = "caml_arrow_group_mean"

external arrow_group_count : nativeint -> nativeint option
  = "caml_arrow_group_count"

external arrow_group_min : nativeint -> string -> nativeint option
  = "caml_arrow_group_min"

external arrow_group_max : nativeint -> string -> nativeint option
  = "caml_arrow_group_max"

external arrow_group_count_distinct : nativeint -> string -> nativeint option
  = "caml_arrow_group_count_distinct"

external arrow_group_multi_aggregate :
  nativeint -> string list -> string list -> string list -> nativeint option
  = "caml_arrow_group_multi_aggregate"

external arrow_array_get_buffer_ptr : nativeint -> (nativeint * int) option
  = "caml_arrow_array_get_buffer_ptr"

external arrow_float64_array_to_bigarray :
  nativeint -> (float, Bigarray.float64_elt, Bigarray.c_layout) Bigarray.Array1.t option
  = "caml_arrow_float64_array_to_bigarray"

external arrow_int64_array_to_bigarray :
  nativeint -> (int64, Bigarray.int64_elt, Bigarray.c_layout) Bigarray.Array1.t option
  = "caml_arrow_int64_array_to_bigarray"

external arrow_compute_sqrt_column : nativeint -> string -> nativeint option
  = "caml_arrow_compute_sqrt_column"

external arrow_compute_abs_column : nativeint -> string -> nativeint option
  = "caml_arrow_compute_abs_column"

external arrow_compute_log_column : nativeint -> string -> nativeint option
  = "caml_arrow_compute_log_column"

external arrow_compute_exp_column : nativeint -> string -> nativeint option
  = "caml_arrow_compute_exp_column"

external arrow_compute_pow_column : nativeint -> string -> float -> nativeint option
  = "caml_arrow_compute_pow_column"

external arrow_compute_sum_column : nativeint -> string -> float option
  = "caml_arrow_compute_sum_column"

external arrow_compute_mean_column : nativeint -> string -> float option
  = "caml_arrow_compute_mean_column"

external arrow_compute_min_column : nativeint -> string -> float option
  = "caml_arrow_compute_min_column"

external arrow_compute_max_column : nativeint -> string -> float option
  = "caml_arrow_compute_max_column"

external arrow_compute_compare_scalar : nativeint -> string -> float -> int -> bool array option
  = "caml_arrow_compute_compare_scalar"

external arrow_column_null_mask : nativeint -> string -> bool array option
  = "caml_arrow_column_null_mask"

external arrow_compute_sort_indices : nativeint -> string -> bool -> int array option
  = "caml_arrow_compute_sort_indices"

external arrow_compute_dense_rank : nativeint -> string -> int option array option
  = "caml_arrow_compute_dense_rank"

external arrow_compute_rank : nativeint -> string -> int -> int option array option
  = "caml_arrow_compute_rank"

external arrow_compute_lag_column : nativeint -> string -> int -> nativeint option
  = "caml_arrow_compute_lag_column"

external arrow_compute_lead_column : nativeint -> string -> int -> nativeint option
  = "caml_arrow_compute_lead_column"

external arrow_group_by_optimized : nativeint -> string list -> nativeint option
  = "caml_arrow_group_by_optimized"
