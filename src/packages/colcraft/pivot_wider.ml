open Ast
open Arrow_table

(*
--# Pivot wider
--#
--# Widens data, increasing the number of columns and decreasing the number of rows.
--#
--# @name pivot_wider
--# @param df :: DataFrame The DataFrame.
--# @param names_from :: String The column to get the name of the output column.
--# @param values_from :: String The column to get the cell values from.
--# @return :: DataFrame The pivoted DataFrame.
--# @example
--#   pivot_wider(df, "name", "value")
--# @family colcraft
--# @export
*)
let register env =
  Env.add "pivot_wider"
    (make_builtin_named ~name:"pivot_wider" ~variadic:true 1 (fun named_args _env ->
      let df_arg = match named_args with
        | (_, VDataFrame df) :: _ -> Some df
        | _ -> None
      in
      
      let get_named k = List.find_map (fun (nk, v) -> if nk = Some k then Some v else None) named_args in
      let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) named_args in
      
      match df_arg with
      | None -> Error.type_error "Function `pivot_wider` expects a DataFrame as first argument."
      | Some df ->
          let names_from_val = match get_named "names_from" with Some v -> Some v | None -> (match positional with _::v::_ -> Some v | _ -> None) in
          let values_from_val = match get_named "values_from" with Some v -> Some v | None -> (match positional with _::_::v::_ -> Some v | _ -> None) in
          
          let names_from = match names_from_val with Some (VString s) -> s | Some (VSymbol s) -> (if String.starts_with ~prefix:"$" s then String.sub s 1 (String.length s - 1) else s) | _ -> "" in
          let values_from = match values_from_val with Some (VString s) -> s | Some (VSymbol s) -> (if String.starts_with ~prefix:"$" s then String.sub s 1 (String.length s - 1) else s) | _ -> "" in
          
          if names_from = "" || values_from = "" then Error.make_error ValueError "Function `pivot_wider` requires `names_from` and `values_from` options." else
          
          let pvt_names_col = Arrow_table.get_string_column df.arrow_table names_from in
          let pvt_names = Array.to_list pvt_names_col |> List.filter_map (fun x -> x) |> List.sort_uniq String.compare in
          
          let orig_nrows = Arrow_table.num_rows df.arrow_table in
          let all_cols = Arrow_table.column_names df.arrow_table in
          let id_cols = List.filter (fun c -> c <> names_from && c <> values_from) all_cols in
          
          (* Find unique rows across id_cols *)
          let get_row_key i = 
            List.map (fun c ->
              match Arrow_table.get_column df.arrow_table c with
              | Some (StringColumn a) -> (match a.(i) with Some s -> s | None -> "NA")
              | Some (FloatColumn a) -> (match a.(i) with Some f -> string_of_float f | None -> "NA")
              | Some (IntColumn a) -> (match a.(i) with Some i -> string_of_int i | None -> "NA")
              | Some (BoolColumn a) -> (match a.(i) with Some b -> string_of_bool b | None -> "NA")
              | _ -> "NA"
            ) id_cols |> String.concat "|"
          in
          
          let row_groups = Hashtbl.create orig_nrows in
          let row_keys = ref [] in
          
          for i = 0 to orig_nrows - 1 do
            let key = get_row_key i in
            if not (Hashtbl.mem row_groups key) then row_keys := key :: !row_keys;
            Hashtbl.add row_groups key i
          done;
          
          let final_row_keys = List.rev !row_keys in
          let new_nrows = List.length final_row_keys in
          
          (* Reconstruct ID cols *)
          let new_id_columns = List.map (fun col_name ->
            let first_idx_of_key key = match Hashtbl.find_all row_groups key with hd::_ -> hd | [] -> 0 in
            let col_data = match Arrow_table.get_column df.arrow_table col_name with
              | Some d -> d
              | None -> NullColumn orig_nrows
            in
            let rep_col = match col_data with
              | IntColumn a -> IntColumn (Array.init new_nrows (fun i -> a.(first_idx_of_key (List.nth final_row_keys i))))
              | FloatColumn a -> FloatColumn (Array.init new_nrows (fun i -> a.(first_idx_of_key (List.nth final_row_keys i))))
              | StringColumn a -> StringColumn (Array.init new_nrows (fun i -> a.(first_idx_of_key (List.nth final_row_keys i))))
              | BoolColumn a -> BoolColumn (Array.init new_nrows (fun i -> a.(first_idx_of_key (List.nth final_row_keys i))))
              | NullColumn _ -> NullColumn new_nrows
            in
            (col_name, rep_col)
          ) id_cols in
          
          (* Reconstruct values cols based on names_from values *)
           let pivot_col_data = Arrow_table.get_column df.arrow_table values_from in
           let build_new_col name_val =
             match pivot_col_data with
             | Some (FloatColumn a) -> FloatColumn (Array.init new_nrows (fun i -> 
                   let indices = Hashtbl.find_all row_groups (List.nth final_row_keys i) in
                   List.find_map (fun idx -> if pvt_names_col.(idx) = Some name_val then a.(idx) else None) indices
               ))
             | Some (IntColumn a) -> IntColumn (Array.init new_nrows (fun i -> 
                   let indices = Hashtbl.find_all row_groups (List.nth final_row_keys i) in
                   List.find_map (fun idx -> if pvt_names_col.(idx) = Some name_val then a.(idx) else None) indices
               ))
             | Some (StringColumn a) -> StringColumn (Array.init new_nrows (fun i -> 
                   let indices = Hashtbl.find_all row_groups (List.nth final_row_keys i) in
                   List.find_map (fun idx -> if pvt_names_col.(idx) = Some name_val then a.(idx) else None) indices
               ))
             | Some (BoolColumn a) -> BoolColumn (Array.init new_nrows (fun i -> 
                   let indices = Hashtbl.find_all row_groups (List.nth final_row_keys i) in
                   List.find_map (fun idx -> if pvt_names_col.(idx) = Some name_val then a.(idx) else None) indices
               ))
             | _ -> NullColumn new_nrows
           in
           
           let new_pivot_columns = List.map (fun name_val -> (name_val, build_new_col name_val)) pvt_names in
           
           let new_columns = new_id_columns @ new_pivot_columns in
           let new_schema = List.map (fun (n, c) -> (n, Arrow_table.column_type_of c)) new_columns in
          
          VDataFrame { arrow_table = { schema = new_schema; columns = new_columns; nrows = new_nrows; native_handle = None } |> Arrow_table.materialize; group_keys = df.group_keys }
    ))
    env
