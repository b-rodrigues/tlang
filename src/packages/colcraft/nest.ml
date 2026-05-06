open Ast
open Arrow_table

let nest_impl (named_args : (string option * value) list) _env =
  match named_args with
  | (_, VDataFrame df) :: rest ->
    let all_names = Arrow_table.column_names df.arrow_table in
    
    let rec resolve_col v =
      match v with
      | VSymbol _ -> (match Utils.extract_column_name v with Some s -> Result.Ok [s] | None -> Result.Ok [])
      | VString s -> Result.Ok [s]
      | VVector arr -> 
          let results = Array.to_list arr |> List.map resolve_col in
          (match List.find_opt Result.is_error results with
           | Some (Result.Error e) -> Result.Error e
           | _ -> Result.Ok (List.concat_map (function Result.Ok s -> s | _ -> []) results))
      | VList items -> 
          let results = List.map snd items |> List.map resolve_col in
          (match List.find_opt Result.is_error results with
           | Some (Result.Error e) -> Result.Error e
           | _ -> Result.Ok (List.concat_map (function Result.Ok s -> s | _ -> []) results))
      | VBuiltin b ->
          (match b.b_func [(None, VDataFrame df)] (ref Env.empty) with
           | VList items -> 
               let names = List.map snd items |> List.filter_map (function 
                 | VString s -> Some s 
                 | VSymbol _ as item_v -> Utils.extract_column_name item_v 
                 | _ -> None)
               in Result.Ok names
           | VError e -> Result.Error e
           | other -> Result.Error (Error.make_error_info TypeError ("Matcher returned " ^ Utils.value_to_string other)))
      | VError e -> Result.Error e
      | _ -> Result.Error (Error.make_error_info TypeError ("Invalid column selection: " ^ Utils.value_to_string v))
    in

    (* Support data = [...] keyword or positional columns *)
    let to_nest_res = match List.assoc_opt (Some "data") rest with
      | Some v -> resolve_col v
      | None ->
          let positional = List.filter (fun (k, _) -> k = None) rest |> List.map snd in
          if positional = [] && df.group_keys <> [] then
            (* Nest everything EXCEPT group keys *)
            Result.Ok (List.filter (fun n -> not (List.mem n df.group_keys)) all_names)
          else
            let results = List.map resolve_col positional in
            match List.find_opt Result.is_error results with
            | Some (Result.Error e) -> Result.Error e
            | _ -> Result.Ok (List.concat_map (function Result.Ok s -> s | _ -> []) results)
    in

    begin match to_nest_res with
    | Result.Error e -> VError e
    | Result.Ok to_nest ->
      let missing = List.filter (fun n -> not (List.mem n all_names)) to_nest in
      if missing <> [] then
        Error.make_error KeyError (Printf.sprintf "Column(s) not found in DataFrame: %s." (String.concat ", " missing))
      else if to_nest = [] then VDataFrame df
      else
        let group_cols = List.filter (fun n -> not (List.mem n to_nest)) all_names in
        let new_col_name = match List.assoc_opt (Some "name") rest with Some (VString s) -> s | _ -> "data" in

        if group_cols = [] then
          (* Nest everything *)
          let sub_table = Arrow_compute.project df.arrow_table to_nest in
          let arrow_col = Arrow_table.ListColumn [|Some sub_table|] in
          let new_table = { 
            Arrow_table.schema = [(new_col_name, ArrowList (ArrowStruct sub_table.schema))];
            columns = [(new_col_name, arrow_col)];
            nrows = 1;
            native_handle = None;
          } in
          VDataFrame { arrow_table = new_table; group_keys = [] }
        else
          let grouped = Arrow_compute.group_by_optimized df.arrow_table group_cols in
          let groups = Arrow_compute.get_ocaml_groups grouped in
          let n_groups = List.length groups in

          if n_groups = 0 then begin
            (* Fast-path for empty input: no groups, produce correct empty schema. *)
            let sub_table = Arrow_compute.project df.arrow_table to_nest in
            let key_schema = List.map (fun k ->
              (k, match Arrow_table.column_type df.arrow_table k with Some t -> t | None -> ArrowNA)
            ) group_cols in
            let key_zero_cols = List.map (fun (k, t) ->
              let col = match t with
                | ArrowInt64 -> IntColumn [||]
                | ArrowFloat64 -> FloatColumn [||]
                | ArrowBoolean -> BoolColumn [||]
                | ArrowString -> StringColumn [||]
                | _ -> NAColumn 0
              in
              (k, col)
            ) key_schema in
            let nested_col = (new_col_name, Arrow_table.ListColumn [||]) in
            let final_schema = key_schema @ [(new_col_name, ArrowList (ArrowStruct sub_table.schema))] in
            VDataFrame {
              arrow_table = {
                Arrow_table.schema = final_schema;
                columns = key_zero_cols @ [nested_col];
                nrows = 0;
                native_handle = None;
              };
              group_keys = [];
            }
          end else begin
          let groups_arr = Array.of_list groups in
          let key_cols = List.map (fun k ->
            match Arrow_table.get_column df.arrow_table k with
            | Some col ->
                (k, Array.init n_groups (fun i ->
                  let (_, indices) = groups_arr.(i) in
                  match indices with
                  | first :: _ -> Arrow_bridge.value_at col first
                  | [] -> (VNA NAGeneric)))
            | None -> (k, Array.make n_groups ((VNA NAGeneric)))
          ) group_cols in

          let nested_data = Array.init n_groups (fun i ->
            let (_, indices) = groups_arr.(i) in
            let sub_table = Arrow_compute.take_rows df.arrow_table indices in
            let project_table = Arrow_compute.project sub_table to_nest in
            Some project_table
          ) in

          let all_cols = List.map (fun (k, v) -> (k, Arrow_bridge.values_to_column v)) key_cols in
          let first_sub = match nested_data.(0) with Some t -> t | None -> Arrow_table.empty in
          let nested_col = (new_col_name, Arrow_table.ListColumn nested_data) in

          let final_cols = all_cols @ [nested_col] in
          let final_schema = List.map (fun (k, _) ->
            (k, match Arrow_table.column_type df.arrow_table k with Some t -> t | None -> ArrowNA)
          ) key_cols @ [(new_col_name, ArrowList (ArrowStruct first_sub.schema))] in

          VDataFrame {
            arrow_table = {
              schema = final_schema;
              columns = final_cols;
              nrows = n_groups;
              native_handle = None
            };
            group_keys = []
          }
          end
    end
  | _ :: _ -> Error.type_error "Function `nest` expects a DataFrame as first argument."
  | [] -> Error.make_error ArityError "Function `nest` requires a DataFrame."

(*
--# Nest columns into sub-dataframes
--#
--# Packs selected columns into nested DataFrame values grouped by the remaining columns.
--# Supports flexible column selection using symbols, strings, or selection helpers
--# (like starts_with, ends_with).
--#
--# If the DataFrame is already grouped (via group_by()) and no columns are
--# specified, nest() will automatically nest all columns except the grouping keys.
--#
--# @name nest
--# @param df :: DataFrame The DataFrame to nest.
--# @param data :: Selection (Optional) Columns or matchers to nest.
--# @param name :: String (Optional) Name for the new nested column, defaults to "data".
--# @param ... :: Selection (Optional) Positional columns to nest if 'data' is not provided.
--# @return :: DataFrame A new DataFrame with grouped keys and a nested list-column.
--# @family colcraft
--# @export
*)
let register env =
  Env.add "nest" (make_builtin_named ~name:"nest" ~variadic:true 1 nest_impl) env
