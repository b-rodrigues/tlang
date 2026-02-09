(* src/arrow/arrow_column.ml *)
(* Column access and views for Arrow-backed DataFrames.                  *)
(* Provides zero-copy column views that keep the backing table alive.    *)
(* Supports both native Arrow tables (via FFI) and pure OCaml storage.   *)

(** A column view — references the backing table to prevent GC collection *)
type column_view = {
  backing : Arrow_table.t;
  column_name : string;
  data : Arrow_table.column_data;
}

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
