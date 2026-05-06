open Ast
open Arrow_table
open Arrow_compute

let nested_schema_hint table col_name =
  match Arrow_table.column_type table col_name with
  | Some (ArrowList (ArrowStruct schema)) -> schema
  | _ -> []

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
                  let nested_schema =
                    match Array.to_list data |> List.find_opt (function Some _ -> true | None -> false) with
                    | Some (Some t) -> t.schema
                    | _ -> nested_schema_hint df.arrow_table col_name
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
                      | ArrowDate -> DateColumn [||]
                      | ArrowTimestamp tz -> DatetimeColumn ([||], tz)
                      | ArrowDictionary -> DictionaryColumn ([||], [], false)
                      | ArrowNA | ArrowList _ | ArrowStruct _ -> NAColumn 0
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
                  let nested_schema = match Array.to_list data |> List.find_opt (function Some t -> t.nrows > 0 | None -> false) with
                    | Some (Some t) -> t.schema
                    | _ -> nested_schema_hint df.arrow_table col_name
                  in
                 
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
                 
                 let final_df_table =
                   match df.arrow_table.native_handle with
                   | Some handle when not handle.freed && Arrow_ffi.arrow_available ->
                       let other_table = project df.arrow_table other_names in
                       let expanded_other = sort_by_indices other_table expansion_indices in
                       let tables_to_stack = List.filter_map (fun x -> x) (Array.to_list data) in
                       let stacked_table = Arrow_table.concatenate tables_to_stack in
                       let current_res = ref expanded_other in
                       List.iter (fun (n, _) ->
                         current_res := Arrow_table.add_column_from_table !current_res n stacked_table n
                       ) nested_schema;
                       !current_res
                   | _ ->
                       let other_schema = List.filter (fun (n, _) -> n <> col_name) df.arrow_table.schema in
                       let other_cols = List.map (fun (name, _) ->
                         match Arrow_table.get_column df.arrow_table name with
                         | Some col -> (name, Arrow_table.take_col col expansion_indices !final_nrows)
                         | None -> (name, Arrow_table.NAColumn !final_nrows)
                       ) other_schema in
                       let tables_to_stack = List.filter_map (fun x -> x) (Array.to_list data) in
                       let stacked_table = Arrow_table.concatenate tables_to_stack in
                       if is_native_backed stacked_table then
                         let base_table = {
                           schema = other_schema;
                           columns = other_cols;
                           nrows = !final_nrows;
                           native_handle = None;
                         } |> materialize in
                         let res = ref base_table in
                         List.iter (fun (n, _) ->
                           res := add_column_from_table !res n stacked_table n
                         ) nested_schema;
                         !res
                       else
                         let nested_cols = List.map (fun (n, _) ->
                           match Arrow_table.get_column stacked_table n with
                           | Some col -> (n, col)
                           | None -> (n, Arrow_table.NAColumn !final_nrows)
                         ) nested_schema in
                         {
                           schema = other_schema @ nested_schema;
                           columns = other_cols @ nested_cols;
                           nrows = !final_nrows;
                           native_handle = None;
                         }
                 in
                  VDataFrame { arrow_table = final_df_table; group_keys = df.group_keys }
            | _ -> Error.type_error (Printf.sprintf "Column `%s` is not a list-column." col_name))
  | _ :: _ -> Error.type_error "Function `unnest` expects a DataFrame as first argument."
  | [] -> Error.make_error ArityError "Function `unnest` requires a DataFrame."

(*
--# Expand nested columns
--#
--# Expands a nested list-column (produced by nest() or similar) back into its
--# constituent rows and columns, effectively duplicating rows of the "parent"
--# DataFrame for every row in the nested table.
--#
--# @name unnest
--# @param df :: DataFrame The DataFrame containing a nested column.
--# @param cols :: Column Selection column to unnest (positional or 'cols=' arg).
--# @return :: DataFrame The expanded DataFrame.
--# @family colcraft
--# @export
*)
let register env =
  Env.add "unnest" (make_builtin_named ~name:"unnest" ~variadic:true 1 unnest_impl) env
