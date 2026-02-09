(* src/arrow/arrow_ffi.ml *)
(* FFI bindings to Apache Arrow C GLib library.                          *)
(* These externals are linked when arrow-glib is available via           *)
(* (foreign_stubs ...) in src/dune, backed by src/ffi/arrow_stubs.c.    *)

(* ===================================================================== *)
(* FFI availability flag — true when Arrow C GLib is linked              *)
(* ===================================================================== *)

let arrow_available = true

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

external arrow_table_get_column_by_name : nativeint -> string -> nativeint option
  = "caml_arrow_table_get_column_by_name"

(* ===================================================================== *)
(* Schema Extraction                                                     *)
(* ===================================================================== *)

(** Returns list of (column_name, type_tag) pairs.
    type_tag: 0=ArrowInt64, 1=ArrowFloat64, 2=ArrowBoolean, 3=ArrowString, 4=ArrowNull *)
external arrow_table_get_schema : nativeint -> (string * int) list
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

(* ===================================================================== *)
(* CSV Reading                                                           *)
(* ===================================================================== *)

external arrow_read_csv : string -> nativeint option
  = "caml_arrow_read_csv"

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

(* ===================================================================== *)
(* Sort                                                                  *)
(* ===================================================================== *)

external arrow_table_sort : nativeint -> string -> bool -> nativeint option
  = "caml_arrow_table_sort"

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
