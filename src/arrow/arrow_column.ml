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
    
    @param table The input Arrow table.
    @param name The name of the column to extract.
    @return [Some view] if found, otherwise [None]. *)
let get_column (table : Arrow_table.t) (name : string) : column_view option =
  match Arrow_table.get_column table name with
  | Some data -> Some { backing = table; column_name = name; data }
  | None -> None

(** Retrieve the Arrow data type of a column view.
    
    @param view The column view.
    @return The associated Arrow data type representation. *)
let column_type (view : column_view) : Arrow_table.arrow_type =
  Arrow_table.column_type_of view.data

(** Retrieve the total row length of a column view.
    
    @param view The column view.
    @return The integer length. *)
let column_length (view : column_view) : int =
  Arrow_table.column_length view.data

(** Retrieve the raw internal column data variant structure.
    
    @param view The column view.
    @return The internal [column_data] structure. *)
let column_data (view : column_view) : Arrow_table.column_data =
  view.data

(** Create a zero-copy Bigarray view over an Arrow column's binary buffer.
    
    @param col The column view.
    @return [Some numeric_view] if successful and supported, otherwise [None]. *)
let zero_copy_view (col : column_view) : numeric_view option =
  match col.backing.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
    (match Arrow_table.column_type_of col.data with
     | Arrow_table.ArrowFloat64 ->
       (match Arrow_ffi.arrow_table_get_column_data handle.ptr col.column_name with
        | Some array_ptr ->
          (match Arrow_ffi.arrow_float64_array_to_bigarray array_ptr with
           | Some ba ->
             (* Keep the backing table alive as long as this view is reachable *)
             ignore (Sys.opaque_identity col.backing);
             Some (FloatView ba)
           | None -> None)
        | None -> None)
     | Arrow_table.ArrowInt64 ->
       (match Arrow_ffi.arrow_table_get_column_data handle.ptr col.column_name with
        | Some array_ptr ->
          (match Arrow_ffi.arrow_int64_array_to_bigarray array_ptr with
           | Some ba ->
             ignore (Sys.opaque_identity col.backing);
             Some (IntView ba)
           | None -> None)
        | None -> None)
     | _ -> None)
  | _ -> None

(** Access a single element from a column view.
    
    @param view The column view.
    @param idx The index of the row to access.
    @return The extracted T-Lang [value], or [VNA NAGeneric] if out of bounds. *)
let get_value_at (view : column_view) (idx : int) : Ast.value =
  let len = column_length view in
  if idx < 0 || idx >= len then Ast.(VNA NAGeneric)
  else
    match view.data with
    | Arrow_table.IntColumn a ->
      (match a.(idx) with Some i -> Ast.VInt i | None -> Ast.VNA Ast.NAInt)
    | Arrow_table.FloatColumn a ->
      (match a.(idx) with Some f -> Ast.VFloat f | None -> Ast.VNA Ast.NAFloat)
    | Arrow_table.BoolColumn a ->
      (match a.(idx) with Some b -> Ast.VBool b | None -> Ast.VNA Ast.NABool)
    | Arrow_table.StringColumn a ->
      (match a.(idx) with Some s -> Ast.VString s | None -> Ast.VNA Ast.NAString)
    | Arrow_table.DateColumn a ->
      (match a.(idx) with Some d -> Ast.VDate d | None -> Ast.VNA Ast.NADate)
    | Arrow_table.DatetimeColumn (a, tz) ->
      (match a.(idx) with Some ts -> Ast.VDatetime (ts, tz) | None -> Ast.VNA Ast.NADate)
    | Arrow_table.NAColumn _ -> Ast.VNA Ast.NAGeneric
    | Arrow_table.DictionaryColumn (a, levels, ordered) ->
      (match a.(idx) with Some i -> Ast.VFactor (i, levels, ordered) | None -> Ast.VNA Ast.NAGeneric)
    | Arrow_table.ListColumn a ->
      (match a.(idx) with Some t -> Ast.VDataFrame { arrow_table = t; group_keys = [] } | None -> Ast.VNA Ast.NAGeneric)

(** Create a slice (sub-view) of a column view.
    
    @param view The source column view.
    @param start The starting row index of the slice.
    @param len The length of the slice.
    @return A new [column_view] sub-slice. *)
let get_slice (view : column_view) (start : int) (len : int) : column_view =
  let total = column_length view in
  let actual_start = max 0 (min start total) in
  let actual_len = max 0 (min len (total - actual_start)) in
  let slice_data = match view.data with
    | Arrow_table.IntColumn a ->
      Arrow_table.IntColumn (Array.sub a actual_start actual_len)
    | Arrow_table.FloatColumn a ->
      Arrow_table.FloatColumn (Array.sub a actual_start actual_len)
    | Arrow_table.BoolColumn a ->
      Arrow_table.BoolColumn (Array.sub a actual_start actual_len)
    | Arrow_table.StringColumn a ->
      Arrow_table.StringColumn (Array.sub a actual_start actual_len)
    | Arrow_table.DateColumn a ->
      Arrow_table.DateColumn (Array.sub a actual_start actual_len)
    | Arrow_table.DatetimeColumn (a, tz) ->
      Arrow_table.DatetimeColumn (Array.sub a actual_start actual_len, tz)
    | Arrow_table.NAColumn _ ->
      Arrow_table.NAColumn actual_len
    | Arrow_table.DictionaryColumn (a, levels, ordered) ->
      Arrow_table.DictionaryColumn (Array.sub a actual_start actual_len, levels, ordered)
    | Arrow_table.ListColumn a ->
      Arrow_table.ListColumn (Array.sub a actual_start actual_len)
  in
  { backing = view.backing; column_name = view.column_name; data = slice_data }

(** Convert a column view to a list of T-Lang runtime values.
    
    @param view The column view.
    @return A list of T-Lang [value] elements. *)
let column_view_to_list (view : column_view) : Ast.value list =
  Array.to_list (Arrow_bridge.column_to_values view.data)
