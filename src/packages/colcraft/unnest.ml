open Ast
open Arrow_table

let unnest_impl (named_args : (string option * value) list) _env =
  match named_args with
  | (_, VDataFrame df) :: rest ->
      let col_to_unnest = match List.filter (fun (k, _) -> k = None) rest with
        | [(_, v)] -> Utils.extract_column_name v
        | _ -> (match List.assoc_opt (Some "cols") rest with
                | Some v -> Utils.extract_column_name v
                | _ -> None)
      in
      
      (match col_to_unnest with
       | None -> Error.make_error ArityError "unnest expects a column to unnest ($col)."
       | Some col_name ->
           match Arrow_table.get_column df.arrow_table col_name with
           | Some (ListColumn data) ->
               let other_names = List.filter (fun n -> n <> col_name) (Arrow_table.column_names df.arrow_table) in
               
               (* 1. Calculate final row count *)
               let final_nrows = ref 0 in
               Array.iter (function Some t -> final_nrows := !final_nrows + t.nrows | None -> ()) data;
               
               if !final_nrows = 0 then begin
                 (* Return a 0-row DataFrame that preserves the expected schema:
                    other columns + the nested columns from the first non-null sub-table. *)
                 let nested_schema =
                   match Array.to_list data |> List.find_opt (function Some _ -> true | None -> false) with
                   | Some (Some t) -> t.schema
                   | _ -> []
                 in
                 let other_schema =
                   List.filter_map (fun (n, t) ->
                     if n = col_name then None else Some (n, t)
                   ) df.arrow_table.schema
                 in
                 let zero_col (_, t) name =
                   let col = match t with
                     | ArrowInt64 -> IntColumn [||]
                     | ArrowFloat64 -> FloatColumn [||]
                     | ArrowBoolean -> BoolColumn [||]
                     | ArrowString -> StringColumn [||]
                     | _ -> NullColumn 0
                   in
                   (name, col)
                 in
                 let other_cols = List.map (fun (n, t) -> zero_col (n, t) n) other_schema in
                 let nested_cols = List.map (fun (n, t) -> zero_col (n, t) n) nested_schema in
                 let final_table = {
                   Arrow_table.schema = other_schema @ nested_schema;
                   columns = other_cols @ nested_cols;
                   nrows = 0;
                   native_handle = None;
                 } in
                 VDataFrame { arrow_table = final_table; group_keys = df.group_keys }
               end else
                 (* 2. Extract nested columns schema from first non-empty nested table *)
                 let nested_schema = match Array.to_list data |> List.find_opt (function Some t -> t.nrows > 0 | None -> false) with
                   | Some (Some t) -> t.schema
                   | _ -> []
                 in
                 
                 (* 3. Build indices for "other" columns expansion *)
                 let expansion_indices = Array.make !final_nrows 0 in
                 let curr = ref 0 in
                 Array.iteri (fun i -> function
                   | Some t -> 
                       for _ = 1 to t.nrows do
                         expansion_indices.(!curr) <- i;
                         incr curr
                       done
                   | None -> ()
                 ) data;
                 
                 let other_cols = List.map (fun name ->
                   match Arrow_table.get_column df.arrow_table name with
                   | Some col -> (name, Arrow_table.take_col col expansion_indices !final_nrows)
                   | None -> (name, Arrow_table.NullColumn !final_nrows)
                 ) other_names in
                 
                 (* 4. Combine nested tables *)
                 let nested_cols = List.map (fun (n, _) ->
                   let combined_data = Array.make !final_nrows VNull in
                   let curr = ref 0 in
                   Array.iter (function
                     | Some t_sub ->
                         (match Arrow_table.get_column t_sub n with
                          | Some col_sub ->
                              let vals = Arrow_bridge.column_to_values col_sub in
                              Array.blit vals 0 combined_data !curr t_sub.nrows;
                              curr := !curr + t_sub.nrows
                          | None -> curr := !curr + t_sub.nrows)
                     | None -> ()
                   ) data;
                   (n, Arrow_bridge.values_to_column combined_data)
                 ) nested_schema in
                 
                 let final_table = {
                   Arrow_table.schema = (List.map (fun (n, _) -> (n, match Arrow_table.column_type df.arrow_table n with Some t -> t | None -> ArrowNull)) other_cols) @ nested_schema;
                   columns = other_cols @ nested_cols;
                   nrows = !final_nrows;
                   native_handle = None;
                 } in
                 VDataFrame { arrow_table = final_table; group_keys = df.group_keys }
           | _ -> Error.type_error (Printf.sprintf "Column `%s` is not a list-column." col_name))
  | _ :: _ -> Error.type_error "Function `unnest` expects a DataFrame as first argument."
  | [] -> Error.make_error ArityError "Function `unnest` requires a DataFrame."

(*
--# Expand nested columns
--#
--# Expands nested list or DataFrame columns back into regular rows and columns.
--#
--# @name unnest
--# @family colcraft
--# @export
*)
let register env =
  Env.add "unnest" (make_builtin_named ~name:"unnest" ~variadic:true 1 unnest_impl) env
