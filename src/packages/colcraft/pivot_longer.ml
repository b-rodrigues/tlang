open Ast
open Arrow_table

(*
--# Pivot longer
--#
--# Lengthens data, increasing the number of rows and decreasing the number of columns.
--#
--# @name pivot_longer
--# @param df :: DataFrame The DataFrame.
--# @param cols :: List[String] The columns to pivot into longer format.
--# @param names_to :: String The name of the new column to hold the column names.
--# @param values_to :: String The name of the new column to hold the values.
--# @return :: DataFrame The pivoted DataFrame.
--# @example
--#   pivot_longer(df, ["A", "B"], "name", "value")
--# @family colcraft
--# @export
*)
let register env =
  Env.add "pivot_longer"
    (make_builtin_named ~name:"pivot_longer" ~variadic:true 1 (fun named_args _env ->
      let df_arg = match named_args with
        | (_, VDataFrame df) :: _ -> Some df
        | _ -> None
      in
      
      let get_named k = List.find_map (fun (nk, v) -> if nk = Some k then Some v else None) named_args in
      let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) named_args in
      
      match df_arg with
      | None -> Error.type_error "Function `pivot_longer` expects a DataFrame as first argument."
      | Some df ->
          let cols_val = match get_named "cols" with Some v -> Some v | None -> (match positional with _::v::_ -> Some v | _ -> None) in
          let names_to_val = match get_named "names_to" with Some v -> Some v | None -> (match positional with _::_::v::_ -> Some v | _ -> None) in
          let values_to_val = match get_named "values_to" with Some v -> Some v | None -> (match positional with _::_::_::v::_ -> Some v | _ -> None) in
          
          let names_to = match names_to_val with Some (VString s) -> s | _ -> "name" in
          let values_to = match values_to_val with Some (VString s) -> s | _ -> "value" in
          
          let cols_to_pivot =
            match cols_val with
            | Some (VList items) -> 
                List.filter_map (fun (_, v) -> 
                  match v with 
                  | VString s -> Some s 
                  | VSymbol s -> Some (if String.starts_with ~prefix:"$" s then String.sub s 1 (String.length s - 1) else s)
                  | _ -> None
                ) items
            | _ -> []
          in
          
          if cols_to_pivot = [] then Error.make_error ValueError "Function `pivot_longer` requires at least one column to pivot." else
          
          (* Identify id cols (columns not being pivoted) *)
          let all_cols = Arrow_table.column_names df.arrow_table in
          let id_cols = List.filter (fun c -> not (List.mem c cols_to_pivot)) all_cols in
          
          (* Calculate new number of rows *)
          let n_pivot_cols = List.length cols_to_pivot in
          let orig_nrows = Arrow_table.num_rows df.arrow_table in
          let new_nrows = orig_nrows * n_pivot_cols in
          
          (* Verify that all pivot cols exist and have a consistent type for values, or fallback to mixed/string.
             For simplicity, let's coerce all to float if numeric, or string if mixed. *)
           
          let pivot_types = List.map (fun c -> Arrow_table.column_type df.arrow_table c) cols_to_pivot in
          let is_all_numeric = List.for_all (function Some ArrowInt64 | Some ArrowFloat64 | Some ArrowNull -> true | _ -> false) pivot_types in
          
          (* Create new ID columns by repeating each value `n_pivot_cols` times *)
          let new_id_columns = List.map (fun col_name ->
            let col_data = match Arrow_table.get_column df.arrow_table col_name with
              | Some d -> d
              | None -> NullColumn orig_nrows
            in
            let rep_col = match col_data with
              | IntColumn a -> IntColumn (Array.init new_nrows (fun i -> a.(i / n_pivot_cols)))
              | FloatColumn a -> FloatColumn (Array.init new_nrows (fun i -> a.(i / n_pivot_cols)))
              | StringColumn a -> StringColumn (Array.init new_nrows (fun i -> a.(i / n_pivot_cols)))
              | BoolColumn a -> BoolColumn (Array.init new_nrows (fun i -> a.(i / n_pivot_cols)))
              | NullColumn _ -> NullColumn new_nrows
            in
            (col_name, rep_col)
          ) id_cols in
          
          (* Create names column *)
          let pivot_names_arr = Array.of_list cols_to_pivot in
          let names_col_data = StringColumn (Array.init new_nrows (fun i -> Some pivot_names_arr.(i mod n_pivot_cols))) in
          
          (* Create values column *)
          let build_values is_num = 
            if is_num then
              let arrays = List.map (fun c -> Arrow_table.get_float_column df.arrow_table c) cols_to_pivot |> Array.of_list in
              FloatColumn (Array.init new_nrows (fun i -> arrays.(i mod n_pivot_cols).(i / n_pivot_cols)))
            else
              let arrays = List.map (fun c -> Arrow_table.get_string_column df.arrow_table c) cols_to_pivot |> Array.of_list in
              StringColumn (Array.init new_nrows (fun i -> arrays.(i mod n_pivot_cols).(i / n_pivot_cols)))
          in
          let values_col_data = build_values is_all_numeric in
          
          let new_columns = new_id_columns @ [(names_to, names_col_data); (values_to, values_col_data)] in
          let new_schema = List.map (fun (n, c) -> (n, Arrow_table.column_type_of c)) new_columns in
          
          VDataFrame { arrow_table = { schema = new_schema; columns = new_columns; nrows = new_nrows; native_handle = None } |> Arrow_table.materialize; group_keys = df.group_keys }
    ))
    env
