(* src/arrow/arrow_compute.ml *)
(* Arrow Compute operations for T's colcraft verbs.                      *)
(* When a table has a native_handle, delegates to Arrow Compute kernels  *)
(* via FFI for zero-copy operations and SIMD acceleration.               *)
(* Falls back to pure OCaml implementations when no native handle.       *)

(** Project (select) columns by name.
    Uses native Arrow projection (zero-copy) when available. *)
let project (t : Arrow_table.t) (names : string list) : Arrow_table.t =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_table_project handle.ptr names with
       | Some new_ptr ->
           let new_schema = List.filter (fun (n, _) -> List.mem n names) t.schema in
           Arrow_table.create_from_native new_ptr new_schema t.nrows
       | None ->
           (* Native project failed — fall back to pure OCaml *)
           Arrow_table.project t names)
  | _ ->
      Arrow_table.project t names

(** Filter rows using a boolean mask.
    Uses native Arrow filter kernel when available. *)
let filter (t : Arrow_table.t) (mask : bool array) : Arrow_table.t =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_table_filter_mask handle.ptr mask with
       | Some new_ptr ->
           let new_nrows = Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 mask in
           Arrow_table.create_from_native new_ptr t.schema new_nrows
       | None ->
           (* Native filter failed — fall back to pure OCaml *)
           Arrow_table.filter_rows t mask)
  | _ ->
      Arrow_table.filter_rows t mask

(** Add or replace a column — delegates to Arrow_table.add_column *)
let add_column = Arrow_table.add_column

(** Take rows by index list — delegates to Arrow_table.take_rows *)
let take_rows = Arrow_table.take_rows

(** Sort table by indices — delegates to Arrow_table.sort_by_indices *)
let sort_by_indices = Arrow_table.sort_by_indices

(** Sort table by column name using native Arrow sort when available.
    Returns a new table sorted by the given column.
    Falls back to None when no native handle is present. *)
let sort_by_column (t : Arrow_table.t) (col_name : string) (ascending : bool) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_table_sort handle.ptr col_name ascending with
       | Some new_ptr ->
           Some (Arrow_table.create_from_native new_ptr t.schema t.nrows)
       | None -> None)
  | _ -> None

(* ===================================================================== *)
(* Scalar Arithmetic Operations                                          *)
(* ===================================================================== *)

(** Helper to rebuild schema from a native table pointer *)
let _schema_from_native (ptr : nativeint) : Arrow_table.arrow_schema =
  let pairs = Arrow_ffi.arrow_table_get_schema ptr in
  List.map (fun (name, tag) -> (name, Arrow_table.arrow_type_of_tag tag)) pairs

(** Add a scalar to every element of a named column.
    Uses Arrow Compute 'add' kernel when native handle is present. *)
let add_scalar (t : Arrow_table.t) (col_name : string) (scalar : float) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_compute_add_scalar handle.ptr col_name scalar with
       | Some new_ptr ->
           let schema = _schema_from_native new_ptr in
           let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
           Some (Arrow_table.create_from_native new_ptr schema nrows)
       | None -> None)
  | _ -> None

(** Multiply every element of a named column by a scalar.
    Uses Arrow Compute 'multiply' kernel when native handle is present. *)
let multiply_scalar (t : Arrow_table.t) (col_name : string) (scalar : float) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_compute_multiply_scalar handle.ptr col_name scalar with
       | Some new_ptr ->
           let schema = _schema_from_native new_ptr in
           let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
           Some (Arrow_table.create_from_native new_ptr schema nrows)
       | None -> None)
  | _ -> None

(** Subtract a scalar from every element of a named column.
    Uses Arrow Compute 'subtract' kernel when native handle is present. *)
let subtract_scalar (t : Arrow_table.t) (col_name : string) (scalar : float) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_compute_subtract_scalar handle.ptr col_name scalar with
       | Some new_ptr ->
           let schema = _schema_from_native new_ptr in
           let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
           Some (Arrow_table.create_from_native new_ptr schema nrows)
       | None -> None)
  | _ -> None

(** Divide every element of a named column by a scalar.
    Uses Arrow Compute 'divide' kernel when native handle is present. *)
let divide_scalar (t : Arrow_table.t) (col_name : string) (scalar : float) : Arrow_table.t option =
  match t.native_handle with
  | Some handle when not handle.Arrow_table.freed ->
      (match Arrow_ffi.arrow_compute_divide_scalar handle.ptr col_name scalar with
       | Some new_ptr ->
           let schema = _schema_from_native new_ptr in
           let nrows = Arrow_ffi.arrow_table_num_rows new_ptr in
           Some (Arrow_table.create_from_native new_ptr schema nrows)
       | None -> None)
  | _ -> None
