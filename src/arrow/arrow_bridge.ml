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
  | Arrow_table.DateColumn a ->
      Array.map (fun v -> match v with Some d -> VDate d | None -> VNA NADate) a
  | Arrow_table.DatetimeColumn (a, tz) ->
      Array.map (fun v -> match v with Some ts -> VDatetime (ts, tz) | None -> VNA NADate) a
  | Arrow_table.NullColumn n ->
      Array.make n (VNA NAGeneric)
  | Arrow_table.DictionaryColumn (a, levels, ordered) ->
      Array.map (fun v -> match v with Some i -> VFactor (i, levels, ordered) | None -> VNA NAGeneric) a
  | Arrow_table.ListColumn a ->
      Array.map (function Some t -> VDataFrame { arrow_table = t; group_keys = [] } | None -> VNA NAGeneric) a

(** Convert a T value array to an Arrow column, inferring the type *)
let values_to_column (values : value array) : Arrow_table.column_data =
  (* Infer column type from non-NA values *)
  let has_int = ref false in
  let has_float = ref false in
  let has_bool = ref false in
  let has_string = ref false in
  let has_date = ref false in
  let has_datetime = ref false in
  let has_factor = ref false in
  let factor_levels = ref [] in
  let factor_ordered = ref false in
  let factor_inconsistent = ref false in
  let has_dataframe = ref false in
  let all_na = ref true in
  Array.iter (fun v ->
    match v with
    | VInt _ -> has_int := true; all_na := false
    | VFloat _ -> has_float := true; all_na := false
    | VBool _ -> has_bool := true; all_na := false
    | VString _ -> has_string := true; all_na := false
    | VDate _ -> has_date := true; all_na := false
    | VDatetime _ -> has_datetime := true; all_na := false
    | VDataFrame _ -> has_dataframe := true; all_na := false
    | VFactor (_, levels, ordered) ->
        all_na := false;
        (match !factor_levels with
         | [] ->
             has_factor := true;
             factor_levels := levels;
             factor_ordered := ordered
         | existing when existing <> levels ->
             (* Inconsistent level sets across factor values; fall back to string *)
             factor_inconsistent := true
         | _ ->
             has_factor := true;
             if not !factor_ordered then factor_ordered := ordered)
    | VNA _ -> ()
    | _ -> has_string := true; all_na := false  (* fallback to string *)
  ) values;
  if !all_na then
    Arrow_table.NullColumn (Array.length values)
  else if !has_dataframe then
    if !has_int || !has_float || !has_bool || !has_string || !has_date || !has_datetime || !has_factor || !factor_inconsistent then
      failwith "values_to_column: mixed DataFrame and non-DataFrame values cannot be stored in a single column"
    else
      Arrow_table.ListColumn (Array.map (function
        | VDataFrame df -> Some df.arrow_table
        | VNA _ -> None
        | _ -> None
      ) values)
  else if !has_factor && not !factor_inconsistent then
    Arrow_table.DictionaryColumn (Array.map (function
      | VFactor (i, _, _) -> Some i
      | VNA _ -> None
      | _ -> None
    ) values, !factor_levels, !factor_ordered)
  else if !has_datetime && not (!has_int || !has_float || !has_bool || !has_string || !has_date || !has_factor) then
    let tz =
      Array.fold_left (fun acc v ->
        match acc, v with
        | Some tz, _ -> Some tz
        | None, VDatetime (_, tz) -> tz
        | None, _ -> None
      ) None values
    in
    Arrow_table.DatetimeColumn (Array.map (function
      | VDatetime (ts, _) -> Some ts
      | VNA _ -> None
      | _ -> None
    ) values, tz)
  else if !has_date && not (!has_int || !has_float || !has_bool || !has_string || !has_datetime || !has_factor) then
    Arrow_table.DateColumn (Array.map (function
      | VDate d -> Some d
      | VNA _ -> None
      | _ -> None
    ) values)
  else if !has_string || !factor_inconsistent then
    Arrow_table.StringColumn (Array.map (fun v ->
      match v with
      | VString s -> Some s
      | VFactor (i, levels, _) -> (match List.nth_opt levels i with Some s -> Some s | None -> None)
      | VNA _ -> None
      | v -> Some (Utils.value_to_string v)
    ) values)
  else if !has_float then
    Arrow_table.FloatColumn (Array.map (function
      | VFloat f -> Some f
      | VInt i -> Some (float_of_int i)
      | VNA _ -> None
      | _ -> None
    ) values)
  else if !has_int then
    Arrow_table.IntColumn (Array.map (function
      | VInt i -> Some i
      | VNA _ -> None
      | _ -> None
    ) values)
  else if !has_bool then
    Arrow_table.BoolColumn (Array.map (function
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
      | Arrow_table.DateColumn a ->
          (match a.(row_idx) with Some d -> VDate d | None -> VNA NADate)
      | Arrow_table.DatetimeColumn (a, tz) ->
          (match a.(row_idx) with Some ts -> VDatetime (ts, tz) | None -> VNA NADate)
      | Arrow_table.NullColumn _ -> VNA NAGeneric
      | Arrow_table.DictionaryColumn (a, levels, ordered) ->
          (match a.(row_idx) with Some i -> VFactor (i, levels, ordered) | None -> VNA NAGeneric)
      | Arrow_table.ListColumn a ->
          (match a.(row_idx) with Some t -> VDataFrame { arrow_table = t; group_keys = [] } | None -> VNA NAGeneric)
    in
    (name, v)
  ) table.schema

(** Create an Arrow table from T value columns *)
let table_from_value_columns (columns : (string * value array) list) (nrows : int) : Arrow_table.t =
  let arrow_columns = List.map (fun (name, values) ->
    (name, values_to_column values)
  ) columns in
  Arrow_table.create arrow_columns nrows |> Arrow_table.materialize

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

(** Recursively prepare a T value for serialization across process boundaries.
    Ensures any DataFrames are materialized and native pointers are cleared. *)
let rec prepare_value_for_serialization (v : value) : value =
  match v with
  | VDataFrame df ->
      VDataFrame { df with arrow_table = Arrow_table.prepare_for_serialization df.arrow_table }
  | VList items ->
      VList (List.map (fun (n, v) -> (n, prepare_value_for_serialization v)) items)
  | VDict pairs ->
      VDict (List.map (fun (k, v) -> (k, prepare_value_for_serialization v)) pairs)
  | VVector arr ->
      VVector (Array.map prepare_value_for_serialization arr)
  | VPipeline p ->
      (* Pipelines store node results, build env vars, and runtime args — cleanse all value-bearing fields *)
      let p_nodes = List.map (fun (n, v) -> (n, prepare_value_for_serialization v)) p.p_nodes in
      let p_env_vars = List.map (fun (node, vars) ->
        (node, List.map (fun (k, v) -> (k, prepare_value_for_serialization v)) vars)
      ) p.p_env_vars in
      let p_args = List.map (fun (node, args) ->
        (node, List.map (fun (k, v) -> (k, prepare_value_for_serialization v)) args)
      ) p.p_args in
      VPipeline { p with p_nodes; p_env_vars; p_args }
  | VNode un ->
      (* Unbuilt nodes carry env_vars and args that may contain DataFrames *)
      let un_env_vars = List.map (fun (k, v) -> (k, prepare_value_for_serialization v)) un.un_env_vars in
      let un_args = List.map (fun (k, v) -> (k, prepare_value_for_serialization v)) un.un_args in
      VNode { un with un_env_vars; un_args }
  | _ -> v
