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
  | ArrowDate
  | ArrowTimestamp of string option
  | ArrowNull
  | ArrowDictionary
  | ArrowList of arrow_type
  | ArrowStruct of arrow_schema

(** Schema: ordered list of (column_name, column_type) *)
and arrow_schema = (string * arrow_type) list

(** Native Arrow handle — wraps a C pointer to GArrowTable with GC safety *)
type native_handle = {
  ptr : nativeint;
  mutable freed : bool;
}

(** Typed columnar data with explicit nullability (NA support) *)
type column_data =
  | IntColumn of int option array
  | FloatColumn of float option array
  | BoolColumn of bool option array
  | StringColumn of string option array
  | DateColumn of int option array
  | DatetimeColumn of int64 option array * string option
  | NullColumn of int
  | DictionaryColumn of int option array * string list * bool
  | ListColumn of t option array

(** Arrow table — columnar storage with schema.
    When native_handle is Some, the table is backed by a native Arrow table
    (created via FFI, e.g. from CSV reading). When None, pure OCaml storage. *)
and t = {
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
  | DateColumn a -> Array.length a
  | DatetimeColumn (a, _) -> Array.length a
  | NullColumn n -> n
  | DictionaryColumn (a, _, _) -> Array.length a
  | ListColumn a -> Array.length a

let column_type_of = function
  | IntColumn _ -> ArrowInt64
  | FloatColumn _ -> ArrowFloat64
  | BoolColumn _ -> ArrowBoolean
  | StringColumn _ -> ArrowString
  | DateColumn _ -> ArrowDate
  | DatetimeColumn (_, tz) -> ArrowTimestamp tz
  | NullColumn _ -> ArrowNull
  | DictionaryColumn _ -> ArrowDictionary
  | ListColumn a ->
      (match Array.find_opt Option.is_some a with
       | Some (Some t) -> ArrowList (ArrowStruct t.schema)
       | _ -> ArrowList ArrowNull)

let arrow_type_to_string = function
  | ArrowInt64 -> "Int64"
  | ArrowFloat64 -> "Float64"
  | ArrowBoolean -> "Boolean"
  | ArrowString -> "String"
  | ArrowDate -> "Date"
  | ArrowTimestamp None -> "Datetime(UTC)"
  | ArrowTimestamp (Some tz) -> "Datetime(" ^ tz ^ ")"
  | ArrowNull -> "Null"
  | ArrowDictionary -> "Dictionary"
  | ArrowList _ -> "List"
  | ArrowStruct _ -> "Struct"

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

let is_native_backed (t : t) : bool =
  match t.native_handle with
  | Some handle when not handle.freed -> true
  | _ -> false

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
            | ArrowDate | ArrowTimestamp _ ->
                (* Native Arrow date/timestamp extraction is not implemented in the
                   current FFI layer yet, so date-like columns stay in the pure
                   OCaml fallback path until those readers are added. *)
                List.assoc_opt name t.columns
            | ArrowNull ->
                Some (NullColumn t.nrows)
            | ArrowDictionary | ArrowList _ | ArrowStruct _ ->
               (* Dictionary, List and Struct are handled via pure OCaml storage fallback *)
               List.assoc_opt name t.columns)
  | _ ->
      (* Fallback to pure OCaml *)
      List.assoc_opt name t.columns

let column_type (t : t) (name : string) : arrow_type option =
  List.assoc_opt name t.schema

let has_column (t : t) (name : string) : bool =
  List.mem_assoc name t.schema

let get_string_column (t : t) (name : string) : string option array =
  match get_column t name with
  | Some (StringColumn a) -> a
  | _ -> Array.make (num_rows t) None

let get_float_column (t : t) (name : string) : float option array =
  match get_column t name with
  | Some (FloatColumn a) -> a
  | Some (IntColumn a) -> Array.map (function Some i -> Some (float_of_int i) | None -> None) a
  | _ -> Array.make (num_rows t) None

let get_int_column (t : t) (name : string) : int option array =
  match get_column t name with
  | Some (IntColumn a) -> a
  | _ -> Array.make (num_rows t) None

let get_bool_column (t : t) (name : string) : bool option array =
  match get_column t name with
  | Some (BoolColumn a) -> a
  | _ -> Array.make (num_rows t) None

let get_int (col : column_data) (row : int) : int option =
  match col with
  | IntColumn a -> if row < Array.length a then a.(row) else None
  | _ -> None

let get_float (col : column_data) (row : int) : float option =
  match col with
  | FloatColumn a -> if row < Array.length a then a.(row) else None
  | IntColumn a -> if row < Array.length a then (match a.(row) with Some i -> Some (float_of_int i) | None -> None) else None
  | _ -> None

let get_bool (col : column_data) (row : int) : bool option =
  match col with
  | BoolColumn a -> if row < Array.length a then a.(row) else None
  | _ -> None

let get_string (col : column_data) (row : int) : string option =
  match col with
  | StringColumn a -> if row < Array.length a then a.(row) else None
  | _ -> None

(* --- Native materialization --- *)

(** Column builders currently supported by Arrow_ffi.arrow_table_new.
    Only basic Arrow-compatible primitive columns can be rebuilt natively today. *)
let is_arrow_table_new_supported = function
  | IntColumn _ | FloatColumn _ | BoolColumn _ | StringColumn _ -> true
  | NullColumn _ | DictionaryColumn _ | ListColumn _ | DateColumn _ | DatetimeColumn _ -> false

(** Materialize a pure OCaml table into a native Arrow-backed one.
    Returns the table itself if it already has a native_handle.
    Tables containing unsupported column builders remain in pure OCaml form. *)
let materialize (t : t) : t =
  match t.native_handle with
  | Some handle when not handle.freed -> t
  | _ ->
      let has_unsupported = List.exists (fun (_, col) -> not (is_arrow_table_new_supported col)) t.columns in
      if has_unsupported then t
      else
        let arrow_int64_tag = 0 in
        let arrow_float64_tag = 1 in
        let arrow_boolean_tag = 2 in
        let arrow_string_tag = 3 in
        let arrow_unsupported_tag = 8 in
        let tag_of = function
          | ArrowInt64 -> arrow_int64_tag
          | ArrowFloat64 -> arrow_float64_tag
          | ArrowBoolean -> arrow_boolean_tag
          | ArrowString -> arrow_string_tag
          | ArrowNull | ArrowDictionary | ArrowDate | ArrowTimestamp _ | ArrowList _ | ArrowStruct _ -> arrow_unsupported_tag
        in
        let ffi_cols = List.map (fun (name, type_) ->
          let data = match List.assoc_opt name t.columns with
            | Some (IntColumn a) -> Array.map (Option.map Obj.repr) a
            | Some (FloatColumn a) -> Array.map (Option.map Obj.repr) a
            | Some (BoolColumn a) -> Array.map (Option.map Obj.repr) a
            | Some (StringColumn a) -> Array.map (Option.map Obj.repr) a
            | Some (NullColumn n) -> Array.make n None
            | Some (DateColumn _) | Some (DatetimeColumn _) | Some (DictionaryColumn _) | Some (ListColumn _) ->
                Array.make t.nrows None
            | None -> Array.make t.nrows None
          in
          (name, tag_of type_, data)
        ) t.schema in
        match Arrow_ffi.arrow_table_new ffi_cols with
        | Some ptr -> create_from_native ptr t.schema t.nrows
        | None -> t

(* --- Table operations --- *)

(** Project (select) columns by name — zero-copy in native Arrow backend.
    Pure OCaml fallback uses O(n*m) list lookup; acceptable for typical column counts. *)
let project (t : t) (names : string list) : t =
  match t.native_handle with
  | Some handle when not handle.freed ->
      (match Arrow_ffi.arrow_table_project handle.ptr names with
       | Some new_ptr ->
           let new_schema = List.map (fun n -> (n, List.assoc n t.schema)) names in
           create_from_native new_ptr new_schema t.nrows
        | None ->
            (* Fallback if native project fails *)
            let schema = List.map (fun n -> (n, List.assoc n t.schema)) names in
            let columns = List.map (fun n -> 
              match get_column t n with
              | Some col -> (n, col)
              | None -> (n, NullColumn t.nrows)
            ) names in
            { schema; columns; nrows = t.nrows; native_handle = None } |> materialize)
  | _ ->
      let schema = List.map (fun n -> (n, List.assoc n t.schema)) names in
      let columns = List.map (fun n -> (n, List.assoc n t.columns)) names in
      { schema; columns; nrows = t.nrows; native_handle = None } |> materialize

(** Add or replace a column.
    Keeps the result on the native Arrow path when all columns are supported
    by the Arrow table builder; otherwise falls back to pure OCaml storage. *)
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
  { schema; columns; nrows = t.nrows; native_handle = None } |> materialize

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
  | DateColumn a -> DateColumn (pick a)
  | DatetimeColumn (a, tz) -> DatetimeColumn (pick a, tz)
  | NullColumn _ -> NullColumn new_nrows
  | DictionaryColumn (a, levels, ordered) -> DictionaryColumn (pick a, levels, ordered)
  | ListColumn a -> ListColumn (pick a)

(** Take elements from a column by index array *)
let take_col (col : column_data) (idx_arr : int array) (new_nrows : int) : column_data =
  match col with
  | IntColumn a -> IntColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))
  | FloatColumn a -> FloatColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))
  | StringColumn a -> StringColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))
  | BoolColumn a -> BoolColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))
  | DateColumn a -> DateColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))
  | DatetimeColumn (a, tz) -> DatetimeColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))), tz)
  | NullColumn _ -> NullColumn new_nrows
  | DictionaryColumn (a, levels, ordered) -> DictionaryColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))), levels, ordered)
  | ListColumn a -> ListColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))

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
            { schema = t.schema; columns; nrows = new_nrows; native_handle = None } |> materialize)
  | _ ->
      let new_nrows = Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 mask in
      let filter_col col = _filter_column_pure col mask new_nrows in
      let columns = List.map (fun (name, col) -> (name, filter_col col)) t.columns in
      { schema = t.schema; columns; nrows = new_nrows; native_handle = None } |> materialize

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
  let columns = List.map (fun (name, col) -> (name, take_col col idx_arr new_nrows)) source_columns in
  { schema = t.schema; columns; nrows = new_nrows; native_handle = None } |> materialize

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
    | DateColumn a -> DateColumn (Array.init n (fun i -> a.(indices.(i))))
    | DatetimeColumn (a, tz) -> DatetimeColumn (Array.init n (fun i -> a.(indices.(i))), tz)
    | NullColumn _ -> NullColumn n
    | DictionaryColumn (a, levels, ordered) -> DictionaryColumn (Array.init n (fun i -> a.(indices.(i))), levels, ordered)
    | ListColumn a -> ListColumn (Array.init n (fun i -> a.(indices.(i))))
  in
  let columns = List.map (fun (name, col) -> (name, sort_col col)) source_columns in
  { schema = t.schema; columns; nrows = n; native_handle = None } |> materialize

(** Rename columns based on an old_name -> new_name mapping. *)
let rename_columns (t : t) (mapping : (string * string) list) : t =
  let old_to_new = List.map (fun (new_n, old_n) -> (old_n, new_n)) mapping in
  let new_schema =
    List.map
      (fun (name, type_) ->
        match List.assoc_opt name old_to_new with
        | Some new_name -> (new_name, type_)
        | None -> (name, type_))
      t.schema
  in
  (* For native-backed tables, load each column into pure OCaml storage first
     so we don't lose data when renaming (materialize only converts pure→native). *)
  let t =
    match t.native_handle with
    | Some _ ->
        let loaded_columns =
          List.map
            (fun (name, _) ->
              let col =
                match get_column t name with
                | Some c -> c
                | None -> NullColumn t.nrows
              in
              (name, col))
            t.schema
        in
        { t with columns = loaded_columns; native_handle = None }
    | None -> t
  in
  let new_columns =
    List.map
      (fun (name, data) ->
        match List.assoc_opt name old_to_new with
        | Some new_name -> (new_name, data)
        | None -> (name, data))
      t.columns
  in
  { t with schema = new_schema; columns = new_columns; native_handle = None } |> materialize
