(* src/arrow/arrow_bridge.ml *)
(* Conversion between Arrow column_data and T runtime values (Ast.value). *)
(* This module bridges the Arrow-backed storage with T's value system.    *)

open Ast

(** Convert an Arrow column to a T value array *)
let column_to_values (col : Arrow_table.column_data) : value array =
  match col with
  | Arrow_table.IntColumn a ->
      Array.map (fun v -> match v with Some i -> VInt i | None -> VNA NAInt) a
  | Arrow_table.FloatColumn a ->
      Array.map (fun v -> match v with Some f -> VFloat f | None -> VNA NAFloat) a
  | Arrow_table.BoolColumn a ->
      Array.map (fun v -> match v with Some b -> VBool b | None -> VNA NABool) a
  | Arrow_table.StringColumn a ->
      Array.map (fun v -> match v with Some s -> VString s | None -> VNA NAString) a
  | Arrow_table.NullColumn n ->
      Array.make n (VNA NAGeneric)

(** Convert a T value array to an Arrow column, inferring the type *)
let values_to_column (values : value array) : Arrow_table.column_data =
  (* Infer column type from non-NA values *)
  let has_int = ref false in
  let has_float = ref false in
  let has_bool = ref false in
  let has_string = ref false in
  let all_na = ref true in
  Array.iter (fun v ->
    match v with
    | VInt _ -> has_int := true; all_na := false
    | VFloat _ -> has_float := true; all_na := false
    | VBool _ -> has_bool := true; all_na := false
    | VString _ -> has_string := true; all_na := false
    | VNA _ -> ()
    | _ -> has_string := true; all_na := false  (* fallback to string *)
  ) values;
  if !all_na then
    Arrow_table.NullColumn (Array.length values)
  else if !has_string then
    Arrow_table.StringColumn (Array.map (fun v ->
      match v with
      | VString s -> Some s
      | VNA _ -> None
      | v -> Some (Utils.value_to_string v)
    ) values)
  else if !has_float then
    Arrow_table.FloatColumn (Array.map (fun v ->
      match v with
      | VFloat f -> Some f
      | VInt i -> Some (float_of_int i)
      | VNA _ -> None
      | _ -> None
    ) values)
  else if !has_int then
    Arrow_table.IntColumn (Array.map (fun v ->
      match v with
      | VInt i -> Some i
      | VNA _ -> None
      | _ -> None
    ) values)
  else if !has_bool then
    Arrow_table.BoolColumn (Array.map (fun v ->
      match v with
      | VBool b -> Some b
      | VNA _ -> None
      | _ -> None
    ) values)
  else
    Arrow_table.NullColumn (Array.length values)

(** Extract a row from an Arrow table as a T Dict (list of name-value pairs).
    For native-backed tables, extracts column data via FFI as needed. *)
let row_to_dict (table : Arrow_table.t) (row_idx : int) : (string * value) list =
  let get_col_data name =
    match Arrow_table.get_column table name with
    | Some col -> col
    | None -> Arrow_table.NullColumn table.nrows
  in
  List.map (fun (name, _) ->
    let col = get_col_data name in
    let v = match col with
      | Arrow_table.IntColumn a ->
          (match a.(row_idx) with Some i -> VInt i | None -> VNA NAInt)
      | Arrow_table.FloatColumn a ->
          (match a.(row_idx) with Some f -> VFloat f | None -> VNA NAFloat)
      | Arrow_table.BoolColumn a ->
          (match a.(row_idx) with Some b -> VBool b | None -> VNA NABool)
      | Arrow_table.StringColumn a ->
          (match a.(row_idx) with Some s -> VString s | None -> VNA NAString)
      | Arrow_table.NullColumn _ -> VNA NAGeneric
    in
    (name, v)
  ) table.schema

(** Create an Arrow table from T value columns *)
let table_from_value_columns (columns : (string * value array) list) (nrows : int) : Arrow_table.t =
  let arrow_columns = List.map (fun (name, values) ->
    (name, values_to_column values)
  ) columns in
  Arrow_table.create arrow_columns nrows

(** Convert an Arrow table back to T value columns.
    For native-backed tables, extracts column data via FFI as needed. *)
let table_to_value_columns (table : Arrow_table.t) : (string * value array) list =
  List.map (fun (name, _) ->
    let col = match Arrow_table.get_column table name with
      | Some c -> c
      | None -> Arrow_table.NullColumn table.nrows
    in
    (name, column_to_values col)
  ) table.schema
