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

type zero_copy_event = {
  op : string;
  reason : string;
}

let env_flag name =
  match Sys.getenv_opt name with
  | Some ("1" | "true" | "yes" | "on") -> true
  | _ -> false

let zero_copy_events : zero_copy_event list ref = ref []
let zero_copy_event_count : int ref = ref 0
let max_zero_copy_events = 1000
let zero_copy_cap_warned : bool ref = ref false

let record_zero_copy_event op reason =
  if env_flag "TLANG_ZERO_COPY_DEBUG" then begin
    if !zero_copy_event_count < max_zero_copy_events then begin
      zero_copy_events := { op; reason } :: !zero_copy_events;
      incr zero_copy_event_count
    end else if not !zero_copy_cap_warned then begin
      zero_copy_cap_warned := true;
      Printf.eprintf
        "[TLANG_ZERO_COPY_DEBUG] zero-copy event buffer capped at %d entries; \
         call take_zero_copy_events() to drain it.\n%!" max_zero_copy_events
    end
  end

let take_zero_copy_events () =
  let events = List.rev !zero_copy_events in
  zero_copy_events := [];
  zero_copy_event_count := 0;
  zero_copy_cap_warned := false;
  events

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
  | 4 -> ArrowDictionary
  | 5 -> ArrowList ArrowNull
  | 7 -> ArrowDate
  | 8 -> ArrowTimestamp None
  | _ -> ArrowNull

let arrow_type_of_schema_tag tag tz =
  match tag with
  | 8 -> ArrowTimestamp tz
  | _ -> arrow_type_of_tag tag

(** Rebuild schema from a native table pointer *)
let schema_from_native_ptr (ptr : nativeint) : arrow_schema =
  let pairs = Arrow_ffi.arrow_table_get_schema ptr in
  List.map (fun (name, tag, tz) -> (name, arrow_type_of_schema_tag tag tz)) pairs

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
  | Some handle -> not handle.freed
  | None -> false

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
      List.map (fun (name, _, _) -> name) schema_pairs
  | _ ->
      List.map fst t.columns

let get_schema (t : t) : arrow_schema = t.schema

(** Slice a column from [offset] for [len] elements *)
let slice_column (col : column_data) (offset : int) (len : int) : column_data =
  match col with
  | IntColumn a -> IntColumn (Array.sub a offset len)
  | FloatColumn a -> FloatColumn (Array.sub a offset len)
  | BoolColumn a -> BoolColumn (Array.sub a offset len)
  | StringColumn a -> StringColumn (Array.sub a offset len)
  | DateColumn a -> DateColumn (Array.sub a offset len)
  | DatetimeColumn (a, tz) -> DatetimeColumn (Array.sub a offset len, tz)
  | NullColumn _ -> NullColumn len
  | DictionaryColumn (a, levels, ordered) -> DictionaryColumn (Array.sub a offset len, levels, ordered)
  | ListColumn a -> ListColumn (Array.sub a offset len)

(** Read a native list-of-struct column and reconstruct as ListColumn.
    Takes the already-fetched array pointer from arrow_table_get_column_data.
    The array_ptr is consumed by arrow_read_list_column (which unrefs it).
    Decomposes the struct child into per-field columns and slices into sub-tables. *)
let read_native_list_column_from_ptr (array_ptr : nativeint) (nrows : int) : column_data option =
  let (child_opt, slices) = Arrow_ffi.arrow_read_list_column array_ptr in
  match child_opt with
  | None -> Some (ListColumn (Array.make (max nrows (Array.length slices)) None))
  | Some child_ptr ->
      let field_infos = Arrow_ffi.arrow_read_struct_fields child_ptr in
      (* Read each field using the appropriate column reader *)
      let field_cols = List.mapi (fun i (fname, ftag) ->
        match Arrow_ffi.arrow_read_struct_field child_ptr i with
        | None -> (fname, ftag, NullColumn 0)
        | Some fptr ->
            let col = match ftag with
              | 0 -> IntColumn (Arrow_ffi.arrow_read_int64_column fptr)
              | 1 -> FloatColumn (Arrow_ffi.arrow_read_float64_column fptr)
              | 2 -> BoolColumn (Arrow_ffi.arrow_read_boolean_column fptr)
              | 3 -> StringColumn (Arrow_ffi.arrow_read_string_column fptr)
              | 4 ->
                  let (idx, lvl, ord) = Arrow_ffi.arrow_read_dictionary_column fptr in
                  DictionaryColumn (idx, lvl, ord)
              | 7 -> DateColumn (Arrow_ffi.arrow_read_date32_column fptr)
              | _ -> Arrow_ffi.arrow_unref fptr; NullColumn 0
            in
            (fname, ftag, col)
      ) field_infos in
      (* Clean up the child struct array *)
      Arrow_ffi.arrow_unref child_ptr;
      let max_len =
        match field_cols with
        | [] -> 0
        | (_, _, col) :: _ -> column_length col
      in
      (* Reconstruct sub-tables by slicing the flattened columns *)
      let nested_opt =
        try
          Some (Array.map (function
            | None -> None
            | Some (offset, len) ->
                if offset < 0 || len < 0 || offset + len > max_len then
                  raise Exit
                else
                let sub_cols = List.map (fun (fname, _, col) ->
                  (fname, slice_column col offset len)
                ) field_cols in
                let sub_schema = List.map (fun (fname, ftag, _) ->
                  (fname, arrow_type_of_tag ftag)
                ) field_cols in
                Some { schema = sub_schema; columns = sub_cols;
                       nrows = len; native_handle = None }
          ) slices)
        with Exit -> None
      in
      match nested_opt with
      | None -> None
      | Some nested -> Some (ListColumn nested)

let get_column (t : t) (name : string) : column_data option =
  match t.native_handle with
  | Some handle when not handle.freed ->
      (* Use native Arrow column extraction *)
      (match List.assoc_opt name t.schema with
       | None -> None
       | Some col_type ->
         match Arrow_ffi.arrow_table_get_column_data handle.ptr name with
         | None ->
             (* If it's an empty table, FFI might return None for columns with 0 chunks.
                Return an empty OCaml column of the correct type. *)
             if t.nrows = 0 then
               (match col_type with
                | ArrowInt64 -> Some (IntColumn [||])
                | ArrowFloat64 -> Some (FloatColumn [||])
                | ArrowBoolean -> Some (BoolColumn [||])
                | ArrowString -> Some (StringColumn [||])
                | ArrowDate -> Some (DateColumn [||])
                | ArrowTimestamp tz -> Some (DatetimeColumn ([||], tz))
                | ArrowNull -> Some (NullColumn 0)
                | ArrowDictionary -> Some (DictionaryColumn ([||], [], false))
                | ArrowList _ -> Some (ListColumn [||])
                | ArrowStruct _ -> Some (NullColumn 0))
             else None
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
            | ArrowDate ->
                Some (DateColumn (Arrow_ffi.arrow_read_date32_column array_ptr))
            | ArrowTimestamp tz ->
                Some (DatetimeColumn (Arrow_ffi.arrow_read_timestamp_column array_ptr, tz))
            | ArrowNull ->
                Arrow_ffi.arrow_unref array_ptr;
                Some (NullColumn t.nrows)
           | ArrowDictionary ->
               let (indices, levels, ordered) =
                 Arrow_ffi.arrow_read_dictionary_column array_ptr in
               Some (DictionaryColumn (indices, levels, ordered))
           | ArrowList _ ->
               (* Read list-of-struct column from native Arrow.
                  array_ptr is consumed by arrow_read_list_column inside. *)
               read_native_list_column_from_ptr array_ptr t.nrows
           | ArrowStruct _ ->
               (* Struct columns use pure OCaml storage fallback *)
               Arrow_ffi.arrow_unref array_ptr;
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
  | Some (DictionaryColumn (indices, levels, _)) ->
      Array.map (function
        | Some idx -> List.nth_opt levels idx
        | None -> None
      ) indices
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
  | DictionaryColumn (indices, levels, _) ->
      if row < Array.length indices then
        (match indices.(row) with
         | Some idx -> List.nth_opt levels idx
         | None -> None)
      else None
  | _ -> None

(* --- Native materialization --- *)

(** Check if a primitive column type tag is supported for native struct fields *)
let is_primitive_tag_supported = function
  | ArrowInt64 | ArrowFloat64 | ArrowBoolean | ArrowString | ArrowDate -> true
  | _ -> false

(** Column builders currently supported by Arrow_ffi.arrow_table_new.
     Primitive columns, null-only columns, dictionary columns, datetime
     columns, and list-of-struct columns with all-primitive fields
     are supported. *)
let is_arrow_table_new_supported = function
  | IntColumn _ | FloatColumn _ | BoolColumn _ | StringColumn _ | DateColumn _ | NullColumn _ | DictionaryColumn _ -> true
  | ListColumn a ->
      (* All non-None sub-tables must have same schema of only primitive types.
         At least one non-None sub-table must exist to determine the struct schema. *)
      let sub_tables = Array.to_list a |> List.filter_map Fun.id in
      (match sub_tables with
       | [] -> false  (* no sub-tables → no struct schema → can't build native list array *)
       | first :: rest ->
           first.schema <> [] &&
           List.for_all (fun t -> t.schema = first.schema) rest &&
           List.for_all (fun (_, ty) -> is_primitive_tag_supported ty) first.schema)
  | DatetimeColumn _ -> true

(** Flatten a ListColumn into (offsets, present_flags, sub_column_specs) for FFI.
    offsets : int array of length nrows+1
    present : bool array of length nrows (true = non-null)
    sub_cols : (string * int * Obj.t array) list — flattened column data *)
let flatten_list_column (nested : t option array) : (int array * bool array * (string * int * Obj.t array) list) =
  let nrows = Array.length nested in
  let arrow_int64_tag = 0 in
  let arrow_float64_tag = 1 in
  let arrow_boolean_tag = 2 in
  let arrow_string_tag = 3 in
  let arrow_date_tag = 7 in
  let sub_tag_of = function
    | ArrowInt64 -> arrow_int64_tag
    | ArrowFloat64 -> arrow_float64_tag
    | ArrowBoolean -> arrow_boolean_tag
    | ArrowString -> arrow_string_tag
    | ArrowDate -> arrow_date_tag
    | _ -> arrow_string_tag (* fallback *)
  in
  (* Compute offsets and total value count *)
  let offsets = Array.make (nrows + 1) 0 in
  let present = Array.make nrows false in
  let total = ref 0 in
  Array.iteri (fun i entry ->
    offsets.(i) <- !total;
    (match entry with
     | Some t -> present.(i) <- true; total := !total + t.nrows
     | None -> present.(i) <- false);
  ) nested;
  offsets.(nrows) <- !total;
  let n_total = !total in
  (* Get sub-column schema from first non-None table *)
  let sub_schema = match Array.find_map Fun.id nested with
    | Some t -> t.schema
    | None -> []
  in
  (* Flatten each sub-column *)
  let pack_opt v = Obj.repr (Option.map Obj.repr v) in
  let sub_cols = List.map (fun (fname, ftype) ->
    let tag = sub_tag_of ftype in
    let flat_data : Obj.t array = Array.make n_total (Obj.repr None) in
    let pos = ref 0 in
    Array.iter (function
      | None -> ()
      | Some sub_t ->
          (match List.assoc_opt fname sub_t.columns with
           | Some (IntColumn a) ->
               Array.iteri (fun j v -> flat_data.(!pos + j) <- pack_opt v) a
           | Some (FloatColumn a) ->
               Array.iteri (fun j v -> flat_data.(!pos + j) <- pack_opt v) a
           | Some (BoolColumn a) ->
               Array.iteri (fun j v -> flat_data.(!pos + j) <- pack_opt v) a
           | Some (StringColumn a) ->
               Array.iteri (fun j v -> flat_data.(!pos + j) <- pack_opt v) a
           | Some (DateColumn a) ->
               Array.iteri (fun j v -> flat_data.(!pos + j) <- pack_opt v) a
           | _ ->
               for j = 0 to sub_t.nrows - 1 do flat_data.(!pos + j) <- Obj.repr None done);
          pos := !pos + sub_t.nrows
    ) nested;
    (fname, tag, flat_data)
  ) sub_schema in
  (offsets, present, sub_cols)

(** Materialize a pure OCaml table into a native Arrow-backed one.
    Returns the table itself if it already has a native_handle.
    Tables containing unsupported column builders remain in pure OCaml form. *)
let materialize (t : t) : t =
  match t.native_handle with
  | Some handle when not handle.freed -> t
  | _ ->
      let has_unsupported =
        (not Arrow_ffi.arrow_available) ||
        List.exists (fun (_, col) -> not (is_arrow_table_new_supported col)) t.columns in
      if has_unsupported then t
      else
        let arrow_int64_tag = 0 in
        let arrow_float64_tag = 1 in
        let arrow_boolean_tag = 2 in
        let arrow_string_tag = 3 in
        let arrow_dictionary_tag = 4 in
        let arrow_list_tag = 5 in
        let arrow_null_tag = 6 in
        let arrow_date_tag = 7 in
        let arrow_timestamp_tag = 8 in
        let arrow_unsupported_tag = 9 in
        let tag_of = function
          | ArrowInt64 -> arrow_int64_tag
          | ArrowFloat64 -> arrow_float64_tag
          | ArrowBoolean -> arrow_boolean_tag
          | ArrowString -> arrow_string_tag
          | ArrowDictionary -> arrow_dictionary_tag
          | ArrowList _ -> arrow_list_tag
          | ArrowNull -> arrow_null_tag
          | ArrowDate -> arrow_date_tag
          | ArrowTimestamp _ -> arrow_timestamp_tag
          | ArrowStruct _ -> arrow_unsupported_tag
        in
        let ffi_cols = List.map (fun (name, type_) ->
          let tag = tag_of type_ in
          let timezone =
            match type_ with
            | ArrowTimestamp tz -> tz
            | _ -> None
          in
          let raw_data : Obj.t = match List.assoc_opt name t.columns with
            | Some (DictionaryColumn (indices, levels, ordered)) ->
                (* Pack as tuple (int option array, string list, bool) for C FFI.
                   The C side reads Field(v_arr, 0/1/2) which works on both
                   OCaml tuples and arrays at the C representation level. *)
                Obj.repr (indices, levels, ordered)
            | Some (ListColumn nested) ->
                (* Pack as tuple (offsets, present, sub_col_specs) for C FFI. *)
                let (offsets, present, sub_cols) = flatten_list_column nested in
                Obj.repr (offsets, present, sub_cols)
            | Some (IntColumn a) -> Obj.repr (Array.map (Option.map Obj.repr) a)
            | Some (FloatColumn a) -> Obj.repr (Array.map (Option.map Obj.repr) a)
            | Some (BoolColumn a) -> Obj.repr (Array.map (Option.map Obj.repr) a)
            | Some (StringColumn a) -> Obj.repr (Array.map (Option.map Obj.repr) a)
            | Some (DateColumn a) -> Obj.repr (Array.map (Option.map Obj.repr) a)
            | Some (DatetimeColumn (a, _)) -> Obj.repr (Array.map (Option.map Obj.repr) a)
            | Some (NullColumn n) -> Obj.repr (Array.make n None)
            | None -> Obj.repr (Array.make t.nrows None)
          in
          (name, tag, timezone, (Obj.obj raw_data : Obj.t array))
        ) t.schema in
        match Arrow_ffi.arrow_table_new ffi_cols with
        | Some ptr -> create_from_native ptr t.schema t.nrows
        | None -> t

(** Prepare a table for transfer across processes (e.g. via Marshal).
    Materializes any native data into OCaml storage and clears the native handle,
    as pointers are not valid in other processes. Also recursively cleanses any
    nested tables inside ListColumn values, regardless of whether the outer table
    has a native handle, to prevent stale pointers after cross-process transfer. *)
let rec prepare_for_serialization (t : t) : t =
  match t.native_handle with
  | Some handle when not handle.freed ->
      (* Materialize columns if they are not already in t.columns.
         We use get_column to ensure we get data from FFI if needed.
         Recursively cleanse any nested tables in ListColumn values. *)
      let columns = List.map (fun (name, _) ->
        let col = match get_column t name with
          | Some data -> data
          | None -> NullColumn t.nrows
        in
        (name, prepare_column_for_serialization col)
      ) t.schema in
      { t with columns; native_handle = None }
  | _ ->
      (* Even when the outer table has no live native handle, nested tables
         inside ListColumn values may still carry native handles. Strip them. *)
      let columns = List.map (fun (name, col) ->
        (name, prepare_column_for_serialization col)
      ) t.columns in
      { t with columns; native_handle = None }

and prepare_column_for_serialization (col : column_data) : column_data =
  match col with
  | ListColumn nested_tables ->
      ListColumn (Array.map (fun entry ->
        match entry with
        | Some nested -> Some (prepare_for_serialization nested)
        | None -> None
      ) nested_tables)
  | _ -> col

(* --- Table operations --- *)

(** Project (select) columns by name — zero-copy in native Arrow backend.
    Pure OCaml fallback uses O(n*m) list lookup; acceptable for typical column counts.
    Unknown column names are mapped to NullColumn to avoid raising Not_found. *)
let project (t : t) (names : string list) : t =
  let safe_assoc_schema n =
    match List.assoc_opt n t.schema with
    | Some ty -> (n, ty)
    | None -> (n, ArrowNull)
  in
  match t.native_handle with
  | Some handle when not handle.freed ->
      (match Arrow_ffi.arrow_table_project handle.ptr names with
       | Some new_ptr ->
           let new_schema = List.map safe_assoc_schema names in
           create_from_native new_ptr new_schema t.nrows
        | None ->
            record_zero_copy_event "project" "native project returned None";
            (* Fallback if native project fails *)
            let schema = List.map safe_assoc_schema names in
            let columns = List.map (fun n ->
              match get_column t n with
              | Some col -> (n, col)
              | None -> (n, NullColumn t.nrows)
            ) names in
            { schema; columns; nrows = t.nrows; native_handle = None } |> materialize)
  | _ ->
      let schema = List.map safe_assoc_schema names in
      let columns = List.map (fun n ->
        match List.assoc_opt n t.columns with
        | Some col -> (n, col)
        | None -> (n, NullColumn t.nrows)
      ) names in
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

(** Add a column to [dst] by taking it from [src]. 
    Stays native if both have native handles. *)
let add_column_from_table (dst : t) (new_name : string) (src : t) (src_name : string) : t =
  match dst.native_handle, src.native_handle with
  | Some h_dst, Some h_src when not h_dst.freed && not h_src.freed ->
      (match Arrow_ffi.arrow_table_add_column_from_table h_dst.ptr new_name h_src.ptr src_name with
       | Some new_ptr ->
           let schema = schema_from_native_ptr new_ptr in
           create_from_native new_ptr schema dst.nrows
       | None -> 
           (* Fallback: materialize column and add it *)
           match get_column src src_name with
           | Some col -> add_column dst new_name col
           | None -> dst)
  | _ ->
      match get_column src src_name with
      | Some col -> add_column dst new_name col
      | None -> dst

let _filter_column_pure (col : column_data) (mask : bool array) (new_nrows : int) : column_data =
  (* Precompute the source indices to avoid O(n²) repeated scanning *)
  let indices = Array.make new_nrows 0 in
  let j = ref 0 in
  Array.iteri (fun src b ->
    if b then begin indices.(!j) <- src; incr j end
  ) mask;
  assert (!j = new_nrows); (* Invariant: mask true-count must match new_nrows *)
  let pick a = Array.init new_nrows (fun i -> a.(indices.(i))) in
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
  let new_nrows = Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 mask in
  match t.native_handle with
  | Some handle when not handle.freed ->
      (match Arrow_ffi.arrow_table_filter_mask handle.ptr mask with
       | Some new_ptr ->
           let schema = schema_from_native_ptr new_ptr in
           create_from_native new_ptr schema new_nrows
       | None ->
           record_zero_copy_event "filter" "native filter returned None";
           (* Native filter failed — materialize columns from FFI first *)
           let filter_col col = _filter_column_pure col mask new_nrows in
           let columns = List.map (fun (name, _) ->
             match get_column t name with
             | Some col -> (name, filter_col col)
             | None -> (name, NullColumn new_nrows)
           ) t.schema in
           { schema = t.schema; columns; nrows = new_nrows; native_handle = None } |> materialize)
  | _ ->
      let filter_col col = _filter_column_pure col mask new_nrows in
      let columns = List.map (fun (name, col) -> (name, filter_col col)) t.columns in
      { schema = t.schema; columns; nrows = new_nrows; native_handle = None } |> materialize

(** Slice rows: offset, length *)
let slice (t : t) (offset : int) (len : int) : t =
  match t.native_handle with
  | Some handle when not handle.freed ->
      (match Arrow_ffi.arrow_table_slice handle.ptr (Int64.of_int offset) (Int64.of_int len) with
       | Some new_ptr ->
           let schema = schema_from_native_ptr new_ptr in
           create_from_native new_ptr schema len
       | None ->
           let columns = List.map (fun (name, _) ->
             let col = match get_column t name with Some c -> c | None -> NullColumn t.nrows in
             (name, slice_column col offset len)
           ) t.schema in
           { schema = t.schema; columns; nrows = len; native_handle = None } |> materialize)
  | _ ->
      let columns = List.map (fun (name, col) -> (name, slice_column col offset len)) t.columns in
      { schema = t.schema; columns; nrows = len; native_handle = None } |> materialize


(** Take rows by index list *)
let take_rows (t : t) (indices : int list) : t =
  match t.native_handle with
  | Some handle when not handle.freed ->
      let idx_arr = Array.of_list indices in
      (match Arrow_ffi.arrow_table_take handle.ptr idx_arr with
       | Some new_ptr ->
           let schema = schema_from_native_ptr new_ptr in
           let new_nrows = List.length indices in
           create_from_native new_ptr schema new_nrows
       | None ->
           (* Fallback if native take fails *)
           let source_columns = List.map (fun (n, _) ->
             match get_column t n with
             | Some data -> (n, data)
             | None -> (n, NullColumn t.nrows)
           ) t.schema in
           let idx_arr = Array.of_list indices in
           let new_nrows = List.length indices in
           let columns = List.map (fun (name, col) -> (name, take_col col idx_arr new_nrows)) source_columns in
           { schema = t.schema; columns; nrows = new_nrows; native_handle = None } |> materialize)
  | _ ->
      let idx_arr = Array.of_list indices in
      let new_nrows = List.length indices in
      let columns = List.map (fun (name, col) -> (name, take_col col idx_arr new_nrows)) t.columns in
      { schema = t.schema; columns; nrows = new_nrows; native_handle = None } |> materialize

(** Reorder rows by index array *)
let sort_by_indices (t : t) (indices : int array) : t =
  match t.native_handle with
  | Some handle when not handle.freed ->
      (match Arrow_ffi.arrow_table_take handle.ptr indices with
       | Some new_ptr ->
           let schema = schema_from_native_ptr new_ptr in
           create_from_native new_ptr schema (Array.length indices)
       | None -> 
           (* Fallback: Materialize native columns if needed, then sort *)
           let source_columns =
             List.map (fun (n, _) ->
               match get_column t n with
               | Some data -> (n, data)
               | None -> (n, NullColumn t.nrows)
             ) t.schema
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
           { schema = t.schema; columns; nrows = n; native_handle = None } |> materialize)
  | _ ->
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
    let columns = List.map (fun (name, col) -> (name, sort_col col)) t.columns in
    { schema = t.schema; columns; nrows = n; native_handle = None } |> materialize

(** Rename columns based on an old_name -> new_name mapping. *)
let rename_columns (t : t) (mapping : (string * string) list) : t =
  match t.native_handle with
  | Some handle when not handle.freed ->
      let rec apply_native_renames current_ptr current_schema renames =
        match renames with
        | [] -> Some (current_ptr, current_schema)
        | (new_n, old_n) :: rest ->
            match Arrow_ffi.arrow_table_rename_column current_ptr old_n new_n with
            | Some next_ptr ->
                let next_schema = schema_from_native_ptr next_ptr in
                apply_native_renames next_ptr next_schema rest
            | None -> None
      in
      (match apply_native_renames handle.ptr t.schema mapping with
       | Some (final_ptr, final_schema) ->
           create_from_native final_ptr final_schema t.nrows
       | None ->
           (* Fallback: materialize all columns and then rename *)
           let old_to_new = List.map (fun (new_n, old_n) -> (old_n, new_n)) mapping in
           let new_schema = List.map (fun (name, ty) ->
             match List.assoc_opt name old_to_new with
             | Some new_name -> (new_name, ty) | None -> (name, ty)) t.schema in
           let columns = List.map (fun (name, _) ->
             let col = match get_column t name with Some c -> c | None -> NullColumn t.nrows in
             match List.assoc_opt name old_to_new with
             | Some new_name -> (new_name, col) | None -> (name, col)) t.schema in
           { schema = new_schema; columns; nrows = t.nrows; native_handle = None } |> materialize)
  | _ ->
      let old_to_new = List.map (fun (new_n, old_n) -> (old_n, new_n)) mapping in
      let new_schema = List.map (fun (name, ty) ->
        match List.assoc_opt name old_to_new with
        | Some new_name -> (new_name, ty) | None -> (name, ty)) t.schema in
      let columns = List.map (fun (name, data) ->
        match List.assoc_opt name old_to_new with
        | Some new_name -> (new_name, data) | None -> (name, data)) t.columns in
      { schema = new_schema; columns; nrows = t.nrows; native_handle = None } |> materialize
