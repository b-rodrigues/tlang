open Ast
open Arrow_table

let nest_impl (named_args : (string option * value) list) _env =
  match named_args with
  | (_, VDataFrame df) :: rest ->
      let all_names = Arrow_table.column_names df.arrow_table in
      
      (* Support data = [...] keyword *)
      let to_nest = match List.assoc_opt (Some "data") rest with
        | Some (VVector arr) -> 
            Array.to_list arr |> List.filter_map Utils.extract_column_name
        | Some (VList items) ->
            List.map snd items |> List.filter_map Utils.extract_column_name
        | Some (VSymbol s) -> (match Utils.extract_column_name (VSymbol s) with Some n -> [n] | None -> [])
        | _ -> 
            (* Positional columns to nest *)
            List.filter (fun (k, _) -> k = None) rest 
            |> List.map snd 
            |> List.filter_map Utils.extract_column_name
      in
      if to_nest = [] then VDataFrame df
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
          let grouped = Arrow_compute.group_by df.arrow_table group_cols in
          let groups = grouped.Arrow_compute.ocaml_groups in
          let n_groups = List.length groups in

          if n_groups = 0 then begin
            (* Fast-path for empty input: no groups, produce correct empty schema. *)
            let sub_table = Arrow_compute.project df.arrow_table to_nest in
            let key_schema = List.map (fun k ->
              (k, match Arrow_table.column_type df.arrow_table k with Some t -> t | None -> ArrowNull)
            ) group_cols in
            let key_zero_cols = List.map (fun (k, t) ->
              let col = match t with
                | ArrowInt64 -> IntColumn [||]
                | ArrowFloat64 -> FloatColumn [||]
                | ArrowBoolean -> BoolColumn [||]
                | ArrowString -> StringColumn [||]
                | _ -> NullColumn 0
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
          let key_cols = List.map (fun k ->
            match Arrow_table.get_column df.arrow_table k with
            | Some col ->
                let vals = Arrow_bridge.column_to_values col in
                (k, Array.init n_groups (fun i ->
                  let (_, indices) = List.nth groups i in
                  vals.(List.hd indices)))
            | None -> (k, Array.make n_groups (VNA NAGeneric))
          ) group_cols in

          let nested_data = Array.init n_groups (fun i ->
            let (_, indices) = List.nth groups i in
            let sub_table = Arrow_compute.take_rows df.arrow_table indices in
            let project_table = Arrow_compute.project sub_table to_nest in
            Some project_table
          ) in

          let all_cols = List.map (fun (k, v) -> (k, Arrow_bridge.values_to_column v)) key_cols in
          let first_sub = match nested_data.(0) with Some t -> t | None -> Arrow_table.empty in
          let nested_col = (new_col_name, Arrow_table.ListColumn nested_data) in

          let final_cols = all_cols @ [nested_col] in
          let final_schema = List.map (fun (k, _) ->
            (k, match Arrow_table.column_type df.arrow_table k with Some t -> t | None -> ArrowNull)
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
  | _ :: _ -> Error.type_error "Function `nest` expects a DataFrame as first argument."
  | [] -> Error.make_error ArityError "Function `nest` requires a DataFrame."

let register env =
  Env.add "nest" (make_builtin_named ~name:"nest" ~variadic:true 1 nest_impl) env
