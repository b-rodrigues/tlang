(* src/arrow/arrow_column.ml *)
(* Column access and views for Arrow-backed DataFrames.                  *)
(* Provides zero-copy column views that keep the backing table alive.    *)
(* Supports both native Arrow tables (via FFI) and pure OCaml storage.   *)

open Bigarray

(** A column view — references the backing table to prevent GC collection *)
type column_view = {
  backing : Arrow_table.t;
  column_name : string;
  data : Arrow_table.column_data;
}

(** A zero-copy numeric view backed by a Bigarray over Arrow memory *)
type numeric_view =
  | FloatView of (float, float64_elt, c_layout) Array1.t
  | IntView of (int64, int64_elt, c_layout) Array1.t

(** Get a column view from an Arrow table.
    For native-backed tables, this extracts column data via FFI. *)
let get_column (table : Arrow_table.t) (name : string) : column_view option =
  match Arrow_table.get_column table name with
  | Some data -> Some { backing = table; column_name = name; data }
  | None -> None

(** Get the Arrow type of a column view *)
let column_type (view : column_view) : Arrow_table.arrow_type =
  Arrow_table.column_type_of view.data

(** Get the length of a column view *)
let column_length (view : column_view) : int =
  Arrow_table.column_length view.data

(** Get the raw column data from a view *)
let column_data (view : column_view) : Arrow_table.column_data =
  view.data

(** Create a zero-copy Bigarray view over an Arrow column's buffer.
    Only works for numeric columns (Float64, Int64) backed by a native
    Arrow table. Returns None for non-numeric types or pure OCaml tables.
    The returned Bigarray shares memory with the Arrow buffer — no copy. *)
let zero_copy_view (col : column_view) : numeric_view option =
  match col.backing.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
    (match Arrow_table.column_type_of col.data with
     | Arrow_table.ArrowFloat64 ->
       (match Arrow_ffi.arrow_table_get_column_data handle.ptr col.column_name with
        | Some array_ptr ->
          (match Arrow_ffi.arrow_array_get_buffer_ptr array_ptr with
           | Some (buf_ptr, byte_len) ->
             let n_elements = byte_len / 8 in (* float64 = 8 bytes *)
             let ba = Arrow_ffi.arrow_bigarray_float64_of_ptr buf_ptr n_elements in
             (* Keep the backing table alive as long as this view is reachable *)
             ignore (Sys.opaque_identity col.backing);
             Some (FloatView ba)
           | None -> None)
        | None -> None)
     | Arrow_table.ArrowInt64 ->
       (match Arrow_ffi.arrow_table_get_column_data handle.ptr col.column_name with
        | Some array_ptr ->
          (match Arrow_ffi.arrow_array_get_buffer_ptr array_ptr with
           | Some (buf_ptr, byte_len) ->
             let n_elements = byte_len / 8 in (* int64 = 8 bytes *)
             let ba = Arrow_ffi.arrow_bigarray_int64_of_ptr buf_ptr n_elements in
             ignore (Sys.opaque_identity col.backing);
             Some (IntView ba)
           | None -> None)
        | None -> None)
     | _ -> None)
  | _ -> None
