(* src/arrow/arrow_table.ml *)
(* Arrow-backed table implementation for T DataFrames.                    *)
(* Supports both native Arrow C GLib tables (via FFI) and pure OCaml     *)
(* columnar storage as a fallback. When a native_handle is present,      *)
(* operations can delegate to Arrow Compute kernels via arrow_ffi.ml.    *)

(** Arrow data types — mirrors Arrow's type system *)
type arrow_type =
  | ArrowInt64
  | ArrowFloat64
  | ArrowBoolean
  | ArrowString
  | ArrowNull

(** Typed columnar data with explicit nullability (NA support) *)
type column_data =
  | IntColumn of int option array
  | FloatColumn of float option array
  | BoolColumn of bool option array
  | StringColumn of string option array
  | NullColumn of int

(** Schema: ordered list of (column_name, column_type) *)
type arrow_schema = (string * arrow_type) list

(** Native Arrow handle — wraps a C pointer to GArrowTable with GC safety *)
type native_handle = {
  ptr : nativeint;
  mutable freed : bool;
}

(** Arrow table — columnar storage with schema.
    When native_handle is Some, the table is backed by a native Arrow table
    (created via FFI, e.g. from CSV reading). When None, pure OCaml storage. *)
type t = {
  schema : arrow_schema;
  columns : (string * column_data) list;
  nrows : int;
  native_handle : native_handle option;
}

(* --- Column utilities --- *)

let column_length = function
  | IntColumn a -> Array.length a
  | FloatColumn a -> Array.length a
  | BoolColumn a -> Array.length a
  | StringColumn a -> Array.length a
  | NullColumn n -> n

let column_type_of = function
  | IntColumn _ -> ArrowInt64
  | FloatColumn _ -> ArrowFloat64
  | BoolColumn _ -> ArrowBoolean
  | StringColumn _ -> ArrowString
  | NullColumn _ -> ArrowNull

let arrow_type_to_string = function
  | ArrowInt64 -> "Int64"
  | ArrowFloat64 -> "Float64"
  | ArrowBoolean -> "Boolean"
  | ArrowString -> "String"
  | ArrowNull -> "Null"

(** Convert a type_tag int (from FFI) to arrow_type *)
let arrow_type_of_tag = function
  | 0 -> ArrowInt64
  | 1 -> ArrowFloat64
  | 2 -> ArrowBoolean
  | 3 -> ArrowString
  | _ -> ArrowNull

(* --- GC Finalizer --- *)

(** Register a GC finalizer that frees the native Arrow table when collected *)
let register_finalizer (handle : native_handle) : unit =
  Gc.finalise (fun h ->
    if not h.freed then begin
      Arrow_ffi.arrow_table_free h.ptr;
      h.freed <- true
    end
  ) handle

(* --- Table constructors --- *)

(** Create a pure OCaml table (no native Arrow backing) *)
let create (columns : (string * column_data) list) (nrows : int) : t =
  let schema = List.map (fun (name, col) -> (name, column_type_of col)) columns in
  { schema; columns; nrows; native_handle = None }

(** Create a table backed by a native Arrow C GLib pointer.
    The pointer is wrapped with a GC finalizer for memory safety. *)
let create_from_native (ptr : nativeint) (schema : arrow_schema) (nrows : int) : t =
  let handle = { ptr; freed = false } in
  register_finalizer handle;
  { schema; columns = []; nrows; native_handle = Some handle }

let empty : t =
  { schema = []; columns = []; nrows = 0; native_handle = None }

(* --- Table queries --- *)

let num_rows (t : t) : int =
  match t.native_handle with
  | Some handle when not handle.freed ->
      Arrow_ffi.arrow_table_num_rows handle.ptr
  | _ -> t.nrows

let num_columns (t : t) : int =
  match t.native_handle with
  | Some handle when not handle.freed ->
      Arrow_ffi.arrow_table_num_columns handle.ptr
  | _ -> List.length t.columns

let column_names (t : t) : string list =
  match t.native_handle with
  | Some handle when not handle.freed ->
      let schema_pairs = Arrow_ffi.arrow_table_get_schema handle.ptr in
      List.map fst schema_pairs
  | _ ->
      List.map fst t.columns

let get_schema (t : t) : arrow_schema = t.schema

let get_column (t : t) (name : string) : column_data option =
  match t.native_handle with
  | Some handle when not handle.freed ->
      (* Use native Arrow column extraction *)
      (match List.assoc_opt name t.schema with
       | None -> None
       | Some col_type ->
         match Arrow_ffi.arrow_table_get_column_data handle.ptr name with
         | None -> None
         | Some array_ptr ->
           match col_type with
           | ArrowInt64 ->
               Some (IntColumn (Arrow_ffi.arrow_read_int64_column array_ptr))
           | ArrowFloat64 ->
               Some (FloatColumn (Arrow_ffi.arrow_read_float64_column array_ptr))
           | ArrowBoolean ->
               Some (BoolColumn (Arrow_ffi.arrow_read_boolean_column array_ptr))
           | ArrowString ->
               Some (StringColumn (Arrow_ffi.arrow_read_string_column array_ptr))
           | ArrowNull ->
               Some (NullColumn t.nrows))
  | _ ->
      (* Fallback to pure OCaml *)
      List.assoc_opt name t.columns

let column_type (t : t) (name : string) : arrow_type option =
  List.assoc_opt name t.schema

let has_column (t : t) (name : string) : bool =
  List.mem_assoc name t.schema

(* --- Table operations --- *)

(** Project (select) columns by name — zero-copy in native Arrow backend.
    Pure OCaml fallback uses O(n*m) list lookup; acceptable for typical column counts. *)
let project (t : t) (names : string list) : t =
  match t.native_handle with
  | Some handle when not handle.freed ->
      (match Arrow_ffi.arrow_table_project handle.ptr names with
       | Some new_ptr ->
           let new_schema = List.filter (fun (n, _) -> List.mem n names) t.schema in
           create_from_native new_ptr new_schema t.nrows
       | None ->
           (* Fallback if native project fails *)
           let columns = List.map (fun n -> (n, List.assoc n t.columns)) names in
           let schema = List.map (fun n -> (n, List.assoc n t.schema)) names in
           { schema; columns; nrows = t.nrows; native_handle = None })
  | _ ->
      let columns = List.map (fun n -> (n, List.assoc n t.columns)) names in
      let schema = List.map (fun n -> (n, List.assoc n t.schema)) names in
      { schema; columns; nrows = t.nrows; native_handle = None }

(** Add or replace a column.
    Note: adding a column to a native-backed table materializes it as pure OCaml. *)
let add_column (t : t) (name : string) (col : column_data) : t =
  (* Materialize native columns if needed *)
  let base_columns =
    match t.native_handle with
    | Some handle when not handle.freed ->
        List.map (fun (n, _) ->
          match get_column t n with
          | Some data -> (n, data)
          | None -> (n, NullColumn t.nrows)
        ) t.schema
    | _ -> t.columns
  in
  let exists = List.mem_assoc name t.schema in
  let columns =
    if exists then
      List.map (fun (n, c) -> if n = name then (n, col) else (n, c)) base_columns
    else
      base_columns @ [(name, col)]
  in
  let typ = column_type_of col in
  let schema =
    if exists then
      List.map (fun (n, ty) -> if n = name then (n, typ) else (n, ty)) t.schema
    else
      t.schema @ [(name, typ)]
  in
  { schema; columns; nrows = t.nrows; native_handle = None }

let _filter_column_pure (col : column_data) (mask : bool array) (new_nrows : int) : column_data =
  let pick a =
    Array.init new_nrows (fun j ->
      let rec find src count =
        if mask.(src) then (if count = j then a.(src) else find (src + 1) (count + 1))
        else find (src + 1) count
      in find 0 0)
  in
  match col with
  | IntColumn a -> IntColumn (pick a)
  | FloatColumn a -> FloatColumn (pick a)
  | BoolColumn a -> BoolColumn (pick a)
  | StringColumn a -> StringColumn (pick a)
  | NullColumn _ -> NullColumn new_nrows

(** Filter rows using a boolean mask *)
let filter_rows (t : t) (mask : bool array) : t =
  match t.native_handle with
  | Some handle when not handle.freed ->
      (match Arrow_ffi.arrow_table_filter_mask handle.ptr mask with
       | Some new_ptr ->
           let new_nrows = Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 mask in
           create_from_native new_ptr t.schema new_nrows
       | None ->
           (* Fallback *)
           let new_nrows = Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 mask in
           let filter_col col = _filter_column_pure col mask new_nrows in
           let columns = List.map (fun (name, col) -> (name, filter_col col)) t.columns in
           { schema = t.schema; columns; nrows = new_nrows; native_handle = None })
  | _ ->
      let new_nrows = Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 mask in
      let filter_col col = _filter_column_pure col mask new_nrows in
      let columns = List.map (fun (name, col) -> (name, filter_col col)) t.columns in
      { schema = t.schema; columns; nrows = new_nrows; native_handle = None }

(** Take rows by index list *)
let take_rows (t : t) (indices : int list) : t =
  (* Materialize native columns if needed, then take rows *)
  let source_columns =
    match t.native_handle with
    | Some handle when not handle.freed ->
        List.map (fun (n, _) ->
          match get_column t n with
          | Some data -> (n, data)
          | None -> (n, NullColumn t.nrows)
        ) t.schema
    | _ -> t.columns
  in
  let new_nrows = List.length indices in
  let idx_arr = Array.of_list indices in
  let take_col = function
    | IntColumn a -> IntColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))
    | FloatColumn a -> FloatColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))
    | BoolColumn a -> BoolColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))
    | StringColumn a -> StringColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))
    | NullColumn _ -> NullColumn new_nrows
  in
  let columns = List.map (fun (name, col) -> (name, take_col col)) source_columns in
  { schema = t.schema; columns; nrows = new_nrows; native_handle = None }

(** Reorder rows by index array *)
let sort_by_indices (t : t) (indices : int array) : t =
  (* Materialize native columns if needed, then sort *)
  let source_columns =
    match t.native_handle with
    | Some handle when not handle.freed ->
        List.map (fun (n, _) ->
          match get_column t n with
          | Some data -> (n, data)
          | None -> (n, NullColumn t.nrows)
        ) t.schema
    | _ -> t.columns
  in
  let n = Array.length indices in
  let sort_col = function
    | IntColumn a -> IntColumn (Array.init n (fun i -> a.(indices.(i))))
    | FloatColumn a -> FloatColumn (Array.init n (fun i -> a.(indices.(i))))
    | BoolColumn a -> BoolColumn (Array.init n (fun i -> a.(indices.(i))))
    | StringColumn a -> StringColumn (Array.init n (fun i -> a.(indices.(i))))
    | NullColumn _ -> NullColumn n
  in
  let columns = List.map (fun (name, col) -> (name, sort_col col)) source_columns in
  { schema = t.schema; columns; nrows = n; native_handle = None }
