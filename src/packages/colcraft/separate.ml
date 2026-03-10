open Ast
open Arrow_table

(*
--# Separate a character column into multiple columns
--#
--# Given either a regular expression or a fixed position, separate() splits
--# a single character column into multiple new columns.
--#
--# @name separate
--# @param df :: DataFrame The DataFrame.
--# @param col :: Symbol The column to separate (use $col syntax).
--# @param into :: List[String] Names of the new columns to create.
--# @param sep :: String (Optional) Regular expression or position to separate at.
--#   Defaults to "[^[:alnum:]]+".
--# @param remove :: Bool (Optional) If true, remove the input column from the result. 
--#   Defaults to true.
--# @return :: DataFrame The separated DataFrame.
--# @example
--#   separate(df, $date, into = ["year", "month", "day"], sep = "-")
--# @family colcraft
--# @export
*)
let register env =
  Env.add "separate"
    (make_builtin_named ~name:"separate" ~variadic:true 1 (fun named_args _env ->
      let df_arg = match named_args with
        | (_, VDataFrame df) :: _ -> Some df
        | _ -> None
      in
      
      let get_named k = List.find_map (fun (nk, v) -> if nk = Some k then Some v else None) named_args in
      let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) named_args in
      
      let col_val = match get_named "col" with Some v -> Some v | None -> (match positional with _::v::_ -> Some v | _ -> None) in
      let col_name = match col_val with Some v -> (match Utils.extract_column_name v with Some s -> s | None -> "") | _ -> "" in
      
      let into_val = match get_named "into" with Some v -> Some v | None -> (match positional with _::_::v::_ -> Some v | _ -> None) in
      let into_cols = match into_val with
        | Some (VList items) -> List.filter_map (fun (_, v) -> match v with VString s -> Some s | _ -> None) items
        | _ -> []
      in
      
      let sep = match get_named "sep" with
        | Some (VString s) -> s
        | _ -> "[^[:alnum:]]+"  (* Default to splitting at non-alphanumeric chars *)
      in
      
      let remove = match get_named "remove" with
        | Some (VBool b) -> b
        | _ -> true
      in

      match df_arg with
      | None -> Error.type_error "Function `separate` expects a DataFrame as first argument."
      | Some df ->
          if col_name = "" || into_cols = [] then
            Error.make_error ValueError "Function `separate` requires `col` and `into` arguments."
          else if not (Arrow_table.has_column df.arrow_table col_name) then
            Error.make_error KeyError (Printf.sprintf "Function `separate`: column `%s` not found." col_name)
          else
            let orig_nrows = Arrow_table.num_rows df.arrow_table in
            let col_data = Arrow_table.get_column df.arrow_table col_name in
            
            let val_to_str = function
              | VString s -> Some s
              | VInt n -> Some (string_of_int n)
              | VFloat f -> Some (string_of_float f)
              | VBool b -> Some (string_of_bool b)
              | VDate d -> 
                  let tm = Unix.gmtime (float_of_int d *. 86400.) in
                  Some (Printf.sprintf "%04d-%02d-%02d" (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday)
              | VNA _ | VNull -> None
              | other -> Some (Utils.value_to_string other)
            in

            match col_data with
            | None -> Error.make_error KeyError (Printf.sprintf "Function `separate`: column `%s` not found." col_name)
            | Some data ->
                let values = Arrow_bridge.column_to_values data in
                let sep_re = Str.regexp sep in
                let n_into = List.length into_cols in
                let split_vals = Array.init orig_nrows (fun i ->
                  match val_to_str values.(i) with
                  | Some s ->
                      let parts = Str.split sep_re s in
                      let n_parts = List.length parts in
                      if n_parts >= n_into then
                        List.filteri (fun i _ -> i < n_into) parts
                      else
                        parts @ (List.init (n_into - n_parts) (fun _ -> ""))
                  | None -> List.init n_into (fun _ -> "NA")
                ) in
                
                (* Create new columns *)
                let new_cols_data = List.mapi (fun i name ->
                  let col_vals = Array.map (fun parts -> 
                    match List.nth_opt parts i with 
                    | Some "NA" | None -> None 
                    | Some s -> Some s
                  ) split_vals in
                  (name, StringColumn col_vals)
                ) into_cols in
                
                let all_names = Arrow_table.column_names df.arrow_table in
                let final_columns = ref [] in
                List.iter (fun name ->
                  if name = col_name then
                    begin
                      if not remove then
                        final_columns := (name, data) :: !final_columns;
                      List.iter (fun (n, d) -> final_columns := (n, d) :: !final_columns) new_cols_data
                    end
                  else
                    final_columns := (name, match Arrow_table.get_column df.arrow_table name with Some d -> d | None -> NullColumn orig_nrows) :: !final_columns
                ) all_names;
                let final_columns = List.rev !final_columns in
                
                let new_schema = List.map (fun (n, c) -> (n, Arrow_table.column_type_of c)) final_columns in
                VDataFrame { arrow_table = { schema = new_schema; columns = final_columns; nrows = orig_nrows; native_handle = None } |> Arrow_table.materialize; group_keys = df.group_keys }
    ))
    env
