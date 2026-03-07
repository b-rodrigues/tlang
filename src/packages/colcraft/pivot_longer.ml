open Ast
open Arrow_table

(*
--# Pivot longer
--#
--# Lengthens data, increasing the number of rows and decreasing the number of columns.
--#
--# @name pivot_longer
--# @param df :: DataFrame The DataFrame.
--# @param ... :: Symbol The columns to pivot into longer format (use $col syntax).
--# @param names_to :: String (Optional) The name of the new column to hold the column names. Defaults to "name".
--# @param values_to :: String (Optional) The name of the new column to hold the values. Defaults to "value".
--# @return :: DataFrame The pivoted DataFrame.
--# @example
--#   pivot_longer(df, $A, $B, names_to = "name", values_to = "value")
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
          let names_to = match get_named "names_to" with Some (VString s) -> s | _ -> "name" in
          let values_to = match get_named "values_to" with Some (VString s) -> s | _ -> "value" in
          
          let cols_to_pivot =
            match get_named "cols" with
            | Some (VList items) -> 
                List.filter_map (fun (_, v) -> Utils.extract_column_name v) items
            | Some v -> (match Utils.extract_column_name v with Some s -> [s] | None -> [])
            | None ->
                (* Extract from positional arguments, excluding the first one (df)
                   and excluding trailing strings which might be names_to/values_to *)
                match positional with
                | _ :: rest ->
                    let col_candidates = List.filter (fun v -> not (Utils.is_string v)) rest in
                    List.filter_map Utils.extract_column_name col_candidates
                | _ -> []
          in
          
          if cols_to_pivot = [] then Error.make_error ValueError "Function `pivot_longer` requires at least one column to pivot (use $col syntax)." else

          (* Validate that all requested pivot columns exist *)
          let all_cols = Arrow_table.column_names df.arrow_table in
          let missing_cols = List.filter (fun c -> not (List.mem c all_cols)) cols_to_pivot in
          if missing_cols <> [] then Error.make_error KeyError (Printf.sprintf "Function `pivot_longer`: column(s) not found in DataFrame: %s" (String.concat ", " missing_cols)) else

          (* Identify id cols (columns not being pivoted) *)
          let id_cols = List.filter (fun c -> not (List.mem c cols_to_pivot)) all_cols in
          
          (* Check for name collisions with existing id columns *)
          if List.mem names_to id_cols then Error.make_error ValueError (Printf.sprintf "Function `pivot_longer`: `names_to` value \"%s\" already exists as a column name." names_to) else
          if List.mem values_to id_cols then Error.make_error ValueError (Printf.sprintf "Function `pivot_longer`: `values_to` value \"%s\" already exists as a column name." values_to) else

          (* Calculate new number of rows *)
          let n_pivot_cols = List.length cols_to_pivot in
          let orig_nrows = Arrow_table.num_rows df.arrow_table in
          let new_nrows = orig_nrows * n_pivot_cols in
          
          (* Determine the output type for the values column:
             - All-integer columns → IntColumn
             - Mixed int/float    → FloatColumn (ints promoted)
             - Anything else      → StringColumn (all values coerced to string) *)
           
          let pivot_types = List.map (fun c -> Arrow_table.get_column df.arrow_table c |> function Some col -> Arrow_table.column_type_of col | None -> ArrowNull) cols_to_pivot in
          let is_all_int = List.for_all (function ArrowInt64 | ArrowNull -> true | _ -> false) pivot_types in
          let is_numeric = List.for_all (function ArrowInt64 | ArrowFloat64 | ArrowNull -> true | _ -> false) pivot_types in
          
          (* Create the ID columns by repeating rows *)
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
              | DictionaryColumn (a, levels, ordered) -> DictionaryColumn (Array.init new_nrows (fun i -> a.(i / n_pivot_cols)), levels, ordered)
            in
            (col_name, rep_col)
          ) id_cols in
          
          (* Create names column *)
          let pivot_names_arr = Array.of_list cols_to_pivot in
          let names_col_data = StringColumn (Array.init new_nrows (fun i -> Some pivot_names_arr.(i mod n_pivot_cols))) in
          
          (* Create values column *)
          let build_values () = 
            if is_all_int then
              let arrays = List.map (fun c -> Arrow_table.get_int_column df.arrow_table c) cols_to_pivot |> Array.of_list in
              IntColumn (Array.init new_nrows (fun i -> arrays.(i mod n_pivot_cols).(i / n_pivot_cols)))
            else if is_numeric then
              let arrays = List.map (fun c -> Arrow_table.get_float_column df.arrow_table c) cols_to_pivot |> Array.of_list in
              FloatColumn (Array.init new_nrows (fun i -> arrays.(i mod n_pivot_cols).(i / n_pivot_cols)))
            else
              (* Mixed types: coerce all column values to string to preserve data *)
              let arrays = List.map (fun c ->
                match Arrow_table.get_column df.arrow_table c with
                | Some (StringColumn a) -> a
                | Some (IntColumn a) -> Array.map (Option.map string_of_int) a
                | Some (FloatColumn a) -> Array.map (Option.map string_of_float) a
                | Some (BoolColumn a) -> Array.map (Option.map string_of_bool) a
                | _ -> Array.make orig_nrows None
              ) cols_to_pivot |> Array.of_list in
              StringColumn (Array.init new_nrows (fun i -> arrays.(i mod n_pivot_cols).(i / n_pivot_cols)))
          in
          let values_col_data = build_values () in
          
          let new_columns = new_id_columns @ [(names_to, names_col_data); (values_to, values_col_data)] in
          let new_schema = List.map (fun (n, c) -> (n, Arrow_table.column_type_of c)) new_columns in
          let new_group_keys =
            let existing_cols = List.map fst new_schema in
            List.filter (fun k -> List.mem k existing_cols) df.group_keys
          in
          
          VDataFrame { arrow_table = { schema = new_schema; columns = new_columns; nrows = new_nrows; native_handle = None } |> Arrow_table.materialize; group_keys = new_group_keys }
    ))
    env
