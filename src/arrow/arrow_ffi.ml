(* src/arrow/arrow_ffi.ml *)
(* FFI bindings to Apache Arrow C GLib library.                          *)
(* These externals are linked when arrow-glib is available via           *)
(* (foreign_stubs ...) in src/dune, backed by src/ffi/arrow_stubs.c.    *)

(* ===================================================================== *)
(* FFI availability flag — true when Arrow C GLib is linked              *)
(* ===================================================================== *)

let arrow_available =
  match Sys.getenv_opt "TLANG_DISABLE_ARROW" with
  | Some ("1" | "true" | "yes" | "on") -> false
  | _ -> true

(* ===================================================================== *)
(* Memory Management                                                     *)
(* ===================================================================== *)

external arrow_table_free : nativeint -> unit
  = "caml_arrow_table_free"

(* ===================================================================== *)
(* Table Queries                                                         *)
(* ===================================================================== *)

external arrow_table_num_rows : nativeint -> int
  = "caml_arrow_table_num_rows"

external arrow_table_num_columns : nativeint -> int
  = "caml_arrow_table_num_columns"

(* ===================================================================== *)
(* Schema Extraction                                                     *)
(* ===================================================================== *)

(** Returns list of (column_name, type_tag, timezone) triples.
    type_tag: 0=ArrowInt64, 1=ArrowFloat64, 2=ArrowBoolean, 3=ArrowString,
              4=ArrowDictionary, 5=ArrowList, 6=ArrowNull, 7=ArrowDate,
              8=ArrowTimestamp. timezone is only populated for timestamps. *)
external arrow_table_get_schema : nativeint -> (string * int * string option) list
  = "caml_arrow_table_get_schema"

(* ===================================================================== *)
(* Column Data Extraction                                                *)
(* ===================================================================== *)

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

external arrow_read_struct_fields : nativeint -> (string * int) list
  = "caml_arrow_read_struct_fields"

external arrow_read_struct_field : nativeint -> int -> nativeint option
  = "caml_arrow_read_struct_field"

external arrow_unref : nativeint -> unit
  = "caml_arrow_unref"

(* ===================================================================== *)
(* CSV Reading                                                           *)
(* ===================================================================== *)

external arrow_read_csv : string -> nativeint option
  = "caml_arrow_read_csv"

external arrow_read_parquet : string -> nativeint option
  = "caml_arrow_read_parquet"

(* ===================================================================== *)
(* IPC Read/Write                                                       *)
(* ===================================================================== *)

external arrow_read_ipc : string -> nativeint option
  = "caml_arrow_read_ipc"

external arrow_write_ipc : nativeint -> string -> bool
  = "caml_arrow_write_ipc"

(* ===================================================================== *)
(* Column Projection (Select)                                            *)
(* ===================================================================== *)

external arrow_table_project : nativeint -> string list -> nativeint option
  = "caml_arrow_table_project"

(* ===================================================================== *)
(* Filter (Boolean mask)                                                 *)
(* ===================================================================== *)

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

(* ===================================================================== *)
(* Sort                                                                  *)
(* ===================================================================== *)

external arrow_table_sort : nativeint -> string -> bool -> nativeint option
  = "caml_arrow_table_sort"

external arrow_table_new : (string * int * string option * 'a array) list -> nativeint option
  = "caml_arrow_table_new"

(* ===================================================================== *)
(* Scalar Arithmetic Operations                                          *)
(* ===================================================================== *)

(** Add a scalar to every element of a named column.
    Returns Some(new_table_ptr) or None on failure. *)
external arrow_compute_add_scalar : nativeint -> string -> float -> nativeint option
  = "caml_arrow_compute_add_scalar"

(** Multiply every element of a named column by a scalar. *)
external arrow_compute_multiply_scalar : nativeint -> string -> float -> nativeint option
  = "caml_arrow_compute_multiply_scalar"

(** Subtract a scalar from every element of a named column. *)
external arrow_compute_subtract_scalar : nativeint -> string -> float -> nativeint option
  = "caml_arrow_compute_subtract_scalar"

(** Divide every element of a named column by a scalar. *)
external arrow_compute_divide_scalar : nativeint -> string -> float -> nativeint option
  = "caml_arrow_compute_divide_scalar"

(* ===================================================================== *)
(* Column-to-Column Arithmetic (Vectorized Processing)                    *)
(* ===================================================================== *)

(** Add two columns element-wise: result[i] = col1[i] + col2[i].
    Returns Some(new_table_ptr) with the result column appended, or None. *)
external arrow_compute_add_columns : nativeint -> string -> string -> string -> nativeint option
  = "caml_arrow_compute_add_columns"

(** Multiply two columns element-wise: result[i] = col1[i] * col2[i]. *)
external arrow_compute_multiply_columns : nativeint -> string -> string -> string -> nativeint option
  = "caml_arrow_compute_multiply_columns"

(** Subtract two columns element-wise: result[i] = col1[i] - col2[i]. *)
external arrow_compute_subtract_columns : nativeint -> string -> string -> string -> nativeint option
  = "caml_arrow_compute_subtract_columns"

(** Divide two columns element-wise: result[i] = col1[i] / col2[i]. *)
external arrow_compute_divide_columns : nativeint -> string -> string -> string -> nativeint option
  = "caml_arrow_compute_divide_columns"

(* ===================================================================== *)
(* Group-By & Aggregation (Phase 3)                                      *)
(* ===================================================================== *)

(** Group a table by key columns. Returns an opaque handle to a
    GroupedTable structure that stores pre-computed group information. *)
external arrow_table_group_by : nativeint -> string list -> nativeint option
  = "caml_arrow_table_group_by"

(** Free a grouped table handle (called from GC finalizer). *)
external arrow_grouped_table_free : nativeint -> unit
  = "caml_arrow_grouped_table_free"

(** Compute sum per group for a named column.
    Returns Some(result_table_ptr) with key columns + aggregated column. *)
external arrow_group_sum : nativeint -> string -> nativeint option
  = "caml_arrow_group_sum"

(** Compute mean per group for a named column.
    Returns Some(result_table_ptr) with key columns + aggregated column. *)
external arrow_group_mean : nativeint -> string -> nativeint option
  = "caml_arrow_group_mean"

(** Compute row count per group.
    Returns Some(result_table_ptr) with key columns + "n" column. *)
external arrow_group_count : nativeint -> nativeint option
  = "caml_arrow_group_count"

(** Compute minimum per group for a named numeric column. *)
external arrow_group_min : nativeint -> string -> nativeint option
  = "caml_arrow_group_min"

(** Compute maximum per group for a named numeric column. *)
external arrow_group_max : nativeint -> string -> nativeint option
  = "caml_arrow_group_max"

(** Compute distinct-count per group for a named column. *)
external arrow_group_count_distinct : nativeint -> string -> nativeint option
  = "caml_arrow_group_count_distinct"

(** Compute multiple aggregations in a single call, building key columns once.
    Args: grouped_table_ptr, agg_types list, col_names list, result_names list.
    agg_types: "sum", "mean", "count", "min", "max", "count_distinct".
    Returns Some(result_table_ptr) with key columns + all agg columns, or None. *)
external arrow_group_multi_aggregate :
  nativeint -> string list -> string list -> string list -> nativeint option
  = "caml_arrow_group_multi_aggregate"

(* ===================================================================== *)
(* Zero-Copy Buffer Access (Phase 4)                                     *)
(* ===================================================================== *)

(** Get the raw data buffer pointer and byte length from an Arrow array.
    Returns Some (pointer, byte_length) or None if buffer is unavailable.
    SAFETY: pointer is only valid while the parent GArrowTable is alive. *)
external arrow_array_get_buffer_ptr : nativeint -> (nativeint * int) option
  = "caml_arrow_array_get_buffer_ptr"

(** Create a zero-copy Float64 Bigarray from an Arrow array.
    Handles buffer access internally — no raw pointers are exposed.
    The Bigarray does NOT own the memory — caller must keep the backing
    Arrow table alive (via GC finalizer on native_handle). *)
external arrow_float64_array_to_bigarray :
  nativeint -> (float, Bigarray.float64_elt, Bigarray.c_layout) Bigarray.Array1.t option
  = "caml_arrow_float64_array_to_bigarray"

(** Create a zero-copy Int64 Bigarray from an Arrow array.
    Handles buffer access internally — no raw pointers are exposed.
    The Bigarray does NOT own the memory — caller must keep the backing
    Arrow table alive (via GC finalizer on native_handle). *)
external arrow_int64_array_to_bigarray :
  nativeint -> (int64, Bigarray.int64_elt, Bigarray.c_layout) Bigarray.Array1.t option
  = "caml_arrow_int64_array_to_bigarray"

(* ===================================================================== *)
(* Unary Math Operations (Phase 5 — Week 1)                              *)
(* ===================================================================== *)

(** Apply sqrt to every element of a named numeric column.
    Returns Some(new_table_ptr) or None on failure. *)
external arrow_compute_sqrt_column : nativeint -> string -> nativeint option
  = "caml_arrow_compute_sqrt_column"

(** Apply abs to every element of a named numeric column. *)
external arrow_compute_abs_column : nativeint -> string -> nativeint option
  = "caml_arrow_compute_abs_column"

(** Apply log (natural logarithm) to every element of a named numeric column. *)
external arrow_compute_log_column : nativeint -> string -> nativeint option
  = "caml_arrow_compute_log_column"

(** Apply exp to every element of a named numeric column. *)
external arrow_compute_exp_column : nativeint -> string -> nativeint option
  = "caml_arrow_compute_exp_column"

(** Raise every element of a named numeric column to a scalar power. *)
external arrow_compute_pow_column : nativeint -> string -> float -> nativeint option
  = "caml_arrow_compute_pow_column"

(* ===================================================================== *)
(* Column-Level Aggregations (Phase 5 — Week 1)                          *)
(* ===================================================================== *)

(** Compute the sum of a named numeric column.
    Returns Some(float) or None if column not found / non-numeric. *)
external arrow_compute_sum_column : nativeint -> string -> float option
  = "caml_arrow_compute_sum_column"

(** Compute the mean of a named numeric column. *)
external arrow_compute_mean_column : nativeint -> string -> float option
  = "caml_arrow_compute_mean_column"

(** Compute the minimum of a named numeric column. *)
external arrow_compute_min_column : nativeint -> string -> float option
  = "caml_arrow_compute_min_column"

(** Compute the maximum of a named numeric column. *)
external arrow_compute_max_column : nativeint -> string -> float option
  = "caml_arrow_compute_max_column"

(* ===================================================================== *)
(* Comparison Operations (Phase 5 — Week 1)                              *)
(* ===================================================================== *)

(** Compare each element of a named numeric column to a scalar.
    Returns Some(bool_array) where each element is the comparison result.
    op_code: 0=eq, 1=lt, 2=gt, 3=le, 4=ge *)
external arrow_compute_compare_scalar : nativeint -> string -> float -> int -> bool array option
  = "caml_arrow_compute_compare_scalar"

(** Read the null bitmap of a named column as a bool mask where true means NA.
    Uses the native Arrow column/chunk validity information without materializing
    full OCaml column values. *)
external arrow_column_null_mask : nativeint -> string -> bool array option
  = "caml_arrow_column_null_mask"
