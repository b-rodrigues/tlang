open Ast
open Arrow_table

(*
--# Pivot wider
--#
--# Widens data, increasing the number of columns and decreasing the number of rows.
--#
--# @name pivot_wider
--# @param df :: DataFrame The DataFrame.
--# @param names_from :: Symbol The column whose values become output column names (use $col syntax).
--# @param values_from :: Symbol The column whose values fill the new columns (use $col syntax).
--# @return :: DataFrame The pivoted DataFrame.
--# @example
--#   pivot_wider(df, names_from = $name, values_from = $value)
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
          
          let is_string_arg = function Some (VString _) -> true | _ -> false in
          if is_string_arg names_from_val then Error.type_error "Function `pivot_wider` expects $column names, but received a String for `names_from`. Use $col syntax instead of a string literal." else
          if is_string_arg values_from_val then Error.type_error "Function `pivot_wider` expects $column names, but received a String for `values_from`. Use $col syntax instead of a string literal." else
          
          let names_from = match names_from_val with Some v -> (match Utils.extract_column_name v with Some s -> s | None -> "") | _ -> "" in
          let values_from = match values_from_val with Some v -> (match Utils.extract_column_name v with Some s -> s | None -> "") | _ -> "" in
          
          if names_from = "" || values_from = "" then Error.make_error ValueError "Function `pivot_wider` requires `names_from` and `values_from` as $column references." else

          (* Validate that names_from exists and is a String column, and that values_from exists *)
          let names_from_col = Arrow_table.get_column df.arrow_table names_from in
          let values_from_col = Arrow_table.get_column df.arrow_table values_from in
          (match names_from_col with
          | None -> Error.make_error KeyError (Printf.sprintf "Function `pivot_wider` expects `names_from` to refer to an existing column, but \"%s\" was not found." names_from)
          | Some (StringColumn _) ->
          (match values_from_col with
          | None -> Error.make_error KeyError (Printf.sprintf "Function `pivot_wider` expects `values_from` to refer to an existing column, but \"%s\" was not found." values_from)
          | Some _ ->
          
          let pvt_names_col = Arrow_table.get_string_column df.arrow_table names_from in
          let pvt_names = Array.to_list pvt_names_col |> List.filter_map (fun x -> x) |> List.sort_uniq String.compare in
          
          let orig_nrows = Arrow_table.num_rows df.arrow_table in
          let all_cols = Arrow_table.column_names df.arrow_table in
          let id_cols = List.filter (fun c -> c <> names_from && c <> values_from) all_cols in

          (* Check for name collisions between pivot-generated columns and existing id columns *)
          let collisions = List.filter (fun n -> List.mem n id_cols) pvt_names in
          if collisions <> [] then Error.make_error ValueError (Printf.sprintf "Function `pivot_wider`: pivot column name(s) collide with existing columns: %s" (String.concat ", " collisions)) else
          
          (* Find unique rows across id_cols using structured value keys to avoid collisions *)
          let get_row_key i =
             List.map (fun c ->
               match Arrow_table.get_column df.arrow_table c with
               | Some (StringColumn a) -> (match a.(i) with Some s -> VString s | None -> (VNA NAGeneric))
               | Some (FloatColumn a) -> (match a.(i) with Some f -> VFloat f | None -> (VNA NAGeneric))
               | Some (IntColumn a) -> (match a.(i) with Some v -> VInt v | None -> (VNA NAGeneric))
               | Some (BoolColumn a) -> (match a.(i) with Some b -> VBool b | None -> (VNA NAGeneric))
               | Some (DateColumn a) -> (match a.(i) with Some d -> VDate d | None -> (VNA NAGeneric))
               | Some (DatetimeColumn (a, tz)) -> (match a.(i) with Some ts -> VDatetime (ts, tz) | None -> (VNA NAGeneric))
               | _ -> (VNA NAGeneric)
             ) id_cols
           in
          
          let row_groups = Hashtbl.create orig_nrows in
          let row_keys = ref [] in
          
          for i = 0 to orig_nrows - 1 do
            let key = get_row_key i in
            if not (Hashtbl.mem row_groups key) then row_keys := key :: !row_keys;
            Hashtbl.add row_groups key i
          done;
          
          let final_row_keys = List.rev !row_keys in
          let final_row_keys_arr = Array.of_list final_row_keys in
          let new_nrows = Array.length final_row_keys_arr in

          (* Precompute first-index and sorted-indices per key to avoid
             re-sorting on every cell access (was O(n^2) before) *)
          let first_index_tbl = Hashtbl.create new_nrows in
          let sorted_indices_tbl = Hashtbl.create new_nrows in
          Array.iter (fun key ->
            if not (Hashtbl.mem first_index_tbl key) then begin
              let sorted = Hashtbl.find_all row_groups key |> List.sort_uniq compare in
              Hashtbl.replace first_index_tbl key (match sorted with hd::_ -> hd | [] -> 0);
              Hashtbl.replace sorted_indices_tbl key sorted
            end
          ) final_row_keys_arr;
          
          (* Reconstruct ID cols — use precomputed first_index for O(1) lookup *)
          let new_id_columns = List.map (fun col_name ->
            let col_data = match Arrow_table.get_column df.arrow_table col_name with
              | Some d -> d
              | None -> NAColumn orig_nrows
            in
            let first_idx key = match Hashtbl.find_opt first_index_tbl key with Some i -> i | None -> 0 in
             let rep_col = match col_data with
               | IntColumn a -> IntColumn (Array.init new_nrows (fun i -> a.(first_idx final_row_keys_arr.(i))))
               | FloatColumn a -> FloatColumn (Array.init new_nrows (fun i -> a.(first_idx final_row_keys_arr.(i))))
               | StringColumn a -> StringColumn (Array.init new_nrows (fun i -> a.(first_idx final_row_keys_arr.(i))))
               | BoolColumn a -> BoolColumn (Array.init new_nrows (fun i -> a.(first_idx final_row_keys_arr.(i))))
               | DateColumn a -> DateColumn (Array.init new_nrows (fun i -> a.(first_idx final_row_keys_arr.(i))))
               | DatetimeColumn (a, tz) -> DatetimeColumn (Array.init new_nrows (fun i -> a.(first_idx final_row_keys_arr.(i))), tz)
               | NAColumn _ -> NAColumn new_nrows
               | DictionaryColumn (a, levels, ordered) -> DictionaryColumn (Array.init new_nrows (fun i -> a.(first_idx final_row_keys_arr.(i))), levels, ordered)
               | ListColumn a -> ListColumn (Array.init new_nrows (fun i -> a.(first_idx final_row_keys_arr.(i))))
             in
            (col_name, rep_col)
          ) id_cols in
          
          (* Reconstruct values cols based on names_from values.
             Use precomputed sorted indices for deterministic first-match behaviour. *)
           let pivot_col_data = Arrow_table.get_column df.arrow_table values_from in
           let build_new_col name_val =
             match pivot_col_data with
             | Some (FloatColumn a) -> FloatColumn (Array.init new_nrows (fun i ->
                   let indices = match Hashtbl.find_opt sorted_indices_tbl final_row_keys_arr.(i) with Some l -> l | None -> [] in
                   List.find_map (fun idx -> if pvt_names_col.(idx) = Some name_val then a.(idx) else None) indices
               ))
             | Some (IntColumn a) -> IntColumn (Array.init new_nrows (fun i ->
                   let indices = match Hashtbl.find_opt sorted_indices_tbl final_row_keys_arr.(i) with Some l -> l | None -> [] in
                   List.find_map (fun idx -> if pvt_names_col.(idx) = Some name_val then a.(idx) else None) indices
               ))
             | Some (StringColumn a) -> StringColumn (Array.init new_nrows (fun i ->
                   let indices = match Hashtbl.find_opt sorted_indices_tbl final_row_keys_arr.(i) with Some l -> l | None -> [] in
                   List.find_map (fun idx -> if pvt_names_col.(idx) = Some name_val then a.(idx) else None) indices
               ))
             | Some (BoolColumn a) -> BoolColumn (Array.init new_nrows (fun i ->
                   let indices = match Hashtbl.find_opt sorted_indices_tbl final_row_keys_arr.(i) with Some l -> l | None -> [] in
                   List.find_map (fun idx -> if pvt_names_col.(idx) = Some name_val then a.(idx) else None) indices
               ))
             | _ -> NAColumn new_nrows
           in
           
           let new_pivot_columns = List.map (fun name_val -> (name_val, build_new_col name_val)) pvt_names in
           
           let new_columns = new_id_columns @ new_pivot_columns in
           let new_schema = List.map (fun (n, c) -> (n, Arrow_table.column_type_of c)) new_columns in
           let new_group_keys =
             List.filter (fun key -> List.exists (fun (name, _) -> name = key) new_columns) df.group_keys
           in
          
          VDataFrame { arrow_table = { schema = new_schema; columns = new_columns; nrows = new_nrows; native_handle = None } |> Arrow_table.materialize; group_keys = new_group_keys })
          | Some _ -> Error.type_error (Printf.sprintf "Function `pivot_wider` expects `names_from` to refer to a String column, but \"%s\" has a non-String type." names_from))
    ))
    env
