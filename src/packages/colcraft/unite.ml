open Ast
open Arrow_table

(*
--# Combine multiple columns into one character column
--#
--# unite() is a convenience function that pastes together multiple columns
--# into a single character column.
--#
--# @name unite
--# @param df :: DataFrame The DataFrame.
--# @param col :: String The name of the new column to create.
--# @param ... :: Symbol The columns to combine (use $col syntax).
--# @param sep :: String (Optional) Separator to use between values. 
--#   Defaults to "_".
--# @param remove :: Bool (Optional) If true, remove the input columns from the result. 
--#   Defaults to true.
--# @param na_rm :: Bool (Optional) If true, missing values will be removed prior to uniting. 
--#   Defaults to false.
--# @return :: DataFrame The united DataFrame.
--# @example
--#   unite(df, "full_name", $first_name, $last_name, sep = " ")
--# @family colcraft
--# @export
*)
let register env =
  Env.add "unite"
    (make_builtin_named ~name:"unite" ~variadic:true 1 (fun named_args _env ->
      let df_arg = match named_args with
        | (_, VDataFrame df) :: _ -> Some df
        | _ -> None
      in
      
      let get_named k = List.find_map (fun (nk, v) -> if nk = Some k then Some v else None) named_args in
      let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) named_args in
      
      let (col_from_named, new_col_name) = match get_named "col" with
        | Some (VString s) -> (true, s)
        | _ ->
            (match positional with
             | _ :: VString s :: _ -> (false, s)
             | _ -> (false, ""))
      in
      
      let cols_variants =
        match positional with
        | _ :: _ when col_from_named ->
            (* col provided as named arg: positional = [df, first_src_col, ...] *)
            (match positional with _ :: tail -> tail | _ -> [])
        | _ :: _ :: tail ->
            (* col provided positionally: positional = [df, new_col_name, first_src_col, ...] *)
            tail
        | _ -> []
      in
      let cols_to_unite = List.filter_map Utils.extract_column_name cols_variants in
      
      let sep = match get_named "sep" with
        | Some (VString s) -> s
        | _ -> "_"
      in
      
      let remove = match get_named "remove" with
        | Some (VBool b) -> b
        | _ -> true
      in
      
      let na_rm = match get_named "na_rm" with
        | Some (VBool b) -> b
        | _ -> false
      in

      match df_arg with
      | None -> Error.type_error "Function `unite` expects a DataFrame as first argument."
      | Some df ->
          if new_col_name = "" || cols_to_unite = [] then
            Error.make_error ValueError "Function `unite` requires `col` and at least one source column."
          else
            let orig_nrows = Arrow_table.num_rows df.arrow_table in
            let all_names = Arrow_table.column_names df.arrow_table in
            
            (* Check existence of columns *)
            let missing = List.filter (fun c -> not (List.mem c all_names)) cols_to_unite in
            if missing <> [] then
              Error.make_error KeyError (Printf.sprintf "Function `unite`: column(s) not found: %s" (String.concat ", " missing))
            else
              
              let get_val_str col_name i =
                match Arrow_table.get_column df.arrow_table col_name with
                | Some (IntColumn a) -> (match a.(i) with Some v -> Some (string_of_int v) | None -> None)
                | Some (FloatColumn a) -> (match a.(i) with Some v -> Some (string_of_float v) | None -> None)
                | Some (StringColumn a) -> (match a.(i) with Some v -> Some v | None -> None)
                | Some (BoolColumn a) -> (match a.(i) with Some v -> Some (string_of_bool v) | None -> None)
                | Some (DateColumn a) -> 
                    (match a.(i) with 
                     | Some d -> 
                         let tm = Unix.gmtime (float_of_int d *. 86400.) in
                         Some (Printf.sprintf "%04d-%02d-%02d" (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday)
                     | None -> None)
                | Some (DatetimeColumn (a, _)) ->
                    (match a.(i) with
                     | Some ts ->
                         let tm = Unix.gmtime (Int64.to_float ts) in
                         Some (Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d" 
                                 (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
                                 tm.tm_hour tm.tm_min tm.tm_sec)
                     | None -> None)
                | _ -> None
              in
              
              let new_col_vals = Array.init orig_nrows (fun i ->
                let parts = List.filter_map (fun col ->
                  match get_val_str col i with
                  | Some s -> Some s
                  | None -> if na_rm then None else Some "NA"
                ) cols_to_unite in
                Some (String.concat sep parts)
              ) in
              
              let new_col_data = (new_col_name, StringColumn new_col_vals) in
              
              (* Find insertion point of FIRST column to unite *)
              let final_columns = ref [] in
              let inserted = ref false in
              
              List.iter (fun name ->
                if List.mem name cols_to_unite then
                  begin
                    if not !inserted then
                      begin
                        final_columns := new_col_data :: !final_columns;
                        inserted := true
                      end;
                    if not remove then
                      final_columns := (name, match Arrow_table.get_column df.arrow_table name with Some d -> d | None -> NAColumn orig_nrows) :: !final_columns
                  end
                else
                  final_columns := (name, match Arrow_table.get_column df.arrow_table name with Some d -> d | None -> NAColumn orig_nrows) :: !final_columns
              ) all_names;
              
              let final_columns = List.rev !final_columns in
              let new_schema = List.map (fun (n, c) -> (n, Arrow_table.column_type_of c)) final_columns in
              VDataFrame { arrow_table = { schema = new_schema; columns = final_columns; nrows = orig_nrows; native_handle = None } |> Arrow_table.materialize; group_keys = df.group_keys }
    ))
    env
