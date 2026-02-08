(* src/arrow/arrow_table.ml *)
(* Arrow-backed table implementation for T DataFrames.                    *)
(* Pure OCaml fallback — when Arrow C GLib is available, the internal     *)
(* representation will use native Arrow arrays via FFI (see arrow_ffi.ml) *)

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

(** Arrow table — columnar storage with schema *)
type t = {
  schema : arrow_schema;
  columns : (string * column_data) list;
  nrows : int;
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

(* --- Table constructors --- *)

let create (columns : (string * column_data) list) (nrows : int) : t =
  let schema = List.map (fun (name, col) -> (name, column_type_of col)) columns in
  { schema; columns; nrows }

let empty : t =
  { schema = []; columns = []; nrows = 0 }

(* --- Table queries --- *)

let num_rows (t : t) : int = t.nrows
let num_columns (t : t) : int = List.length t.columns
let column_names (t : t) : string list = List.map fst t.columns
let get_schema (t : t) : arrow_schema = t.schema

let get_column (t : t) (name : string) : column_data option =
  List.assoc_opt name t.columns

let column_type (t : t) (name : string) : arrow_type option =
  List.assoc_opt name t.schema

let has_column (t : t) (name : string) : bool =
  List.mem_assoc name t.columns

(* --- Table operations --- *)

(** Project (select) columns by name — zero-copy *)
let project (t : t) (names : string list) : t =
  let columns = List.map (fun n -> (n, List.assoc n t.columns)) names in
  let schema = List.map (fun n -> (n, List.assoc n t.schema)) names in
  { schema; columns; nrows = t.nrows }

(** Add or replace a column *)
let add_column (t : t) (name : string) (col : column_data) : t =
  let exists = List.mem_assoc name t.columns in
  let columns =
    if exists then
      List.map (fun (n, c) -> if n = name then (n, col) else (n, c)) t.columns
    else
      t.columns @ [(name, col)]
  in
  let typ = column_type_of col in
  let schema =
    if exists then
      List.map (fun (n, ty) -> if n = name then (n, typ) else (n, ty)) t.schema
    else
      t.schema @ [(name, typ)]
  in
  { schema; columns; nrows = t.nrows }

(** Filter rows using a boolean mask *)
let filter_rows (t : t) (mask : bool array) : t =
  let new_nrows = Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 mask in
  let filter_col = function
    | IntColumn a ->
        IntColumn (Array.init new_nrows (fun j ->
          let rec find src count =
            if mask.(src) then (if count = j then a.(src) else find (src + 1) (count + 1))
            else find (src + 1) count
          in find 0 0))
    | FloatColumn a ->
        FloatColumn (Array.init new_nrows (fun j ->
          let rec find src count =
            if mask.(src) then (if count = j then a.(src) else find (src + 1) (count + 1))
            else find (src + 1) count
          in find 0 0))
    | BoolColumn a ->
        BoolColumn (Array.init new_nrows (fun j ->
          let rec find src count =
            if mask.(src) then (if count = j then a.(src) else find (src + 1) (count + 1))
            else find (src + 1) count
          in find 0 0))
    | StringColumn a ->
        StringColumn (Array.init new_nrows (fun j ->
          let rec find src count =
            if mask.(src) then (if count = j then a.(src) else find (src + 1) (count + 1))
            else find (src + 1) count
          in find 0 0))
    | NullColumn _ -> NullColumn new_nrows
  in
  let columns = List.map (fun (name, col) -> (name, filter_col col)) t.columns in
  { schema = t.schema; columns; nrows = new_nrows }

(** Take rows by index list *)
let take_rows (t : t) (indices : int list) : t =
  let new_nrows = List.length indices in
  let idx_arr = Array.of_list indices in
  let take_col = function
    | IntColumn a -> IntColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))
    | FloatColumn a -> FloatColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))
    | BoolColumn a -> BoolColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))
    | StringColumn a -> StringColumn (Array.init new_nrows (fun i -> a.(idx_arr.(i))))
    | NullColumn _ -> NullColumn new_nrows
  in
  let columns = List.map (fun (name, col) -> (name, take_col col)) t.columns in
  { schema = t.schema; columns; nrows = new_nrows }

(** Reorder rows by index array *)
let sort_by_indices (t : t) (indices : int array) : t =
  let n = Array.length indices in
  let sort_col = function
    | IntColumn a -> IntColumn (Array.init n (fun i -> a.(indices.(i))))
    | FloatColumn a -> FloatColumn (Array.init n (fun i -> a.(indices.(i))))
    | BoolColumn a -> BoolColumn (Array.init n (fun i -> a.(indices.(i))))
    | StringColumn a -> StringColumn (Array.init n (fun i -> a.(indices.(i))))
    | NullColumn _ -> NullColumn n
  in
  let columns = List.map (fun (name, col) -> (name, sort_col col)) t.columns in
  { schema = t.schema; columns; nrows = n }
