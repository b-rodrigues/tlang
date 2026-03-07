open Ast
open Arrow_table

(*
--# Replace missing values
--#
--# replace_na() replaces missing values with specified values.
--#
--# @name replace_na
--# @param df :: DataFrame The DataFrame.
--# @param replace :: Dict A list of named values to use for replacing NA.
--# @return :: DataFrame The DataFrame with NA replaced.
--# @example
--#   replace_na(df, [age: 0, score: 0])
--# @family colcraft
--# @export
*)
let register env =
  Env.add "replace_na"
    (make_builtin_named ~name:"replace_na" ~variadic:true 1 (fun named_args _env ->
      let df_arg = match named_args with
        | (_, VDataFrame df) :: _ -> Some df
        | _ -> None
      in
      
      let get_named k = List.find_map (fun (nk, v) -> if nk = Some k then Some v else None) named_args in
      let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) named_args in
      
      let replace_dict = match get_named "replace" with
        | Some (VDict d) -> d
        | _ -> (match positional with _::VDict d:: _ -> d | _ -> [])
      in
      
      match df_arg with
      | None -> Error.type_error "Function `replace_na` expects a DataFrame as first argument."
      | Some df ->
          if replace_dict = [] then VDataFrame df else
          
          let orig_nrows = Arrow_table.num_rows df.arrow_table in
          let all_cols = Arrow_table.column_names df.arrow_table in
          
          let new_columns = List.map (fun col_name ->
            let col_data = match Arrow_table.get_column df.arrow_table col_name with Some d -> d | None -> NullColumn orig_nrows in
            match List.assoc_opt col_name replace_dict with
            | Some replace_val ->
              begin
                match col_data with
                | IntColumn a ->
                    let fill_i = match replace_val with VInt i -> Some i | VFloat f -> Some (int_of_float f) | _ -> None in
                    (col_name, IntColumn (Array.init orig_nrows (fun i -> match a.(i) with Some x -> Some x | None -> fill_i)))
                | FloatColumn a ->
                    let fill_f = match replace_val with VFloat f -> Some f | VInt i -> Some (float_of_int i) | _ -> None in
                    (col_name, FloatColumn (Array.init orig_nrows (fun i -> match a.(i) with Some x -> Some x | None -> fill_f)))
                | StringColumn a ->
                    let fill_s = match replace_val with VString s -> Some s | _ -> None in
                    (col_name, StringColumn (Array.init orig_nrows (fun i -> match a.(i) with Some x -> Some x | None -> fill_s)))
                | BoolColumn a ->
                    let fill_b = match replace_val with VBool b -> Some b | _ -> None in
                    (col_name, BoolColumn (Array.init orig_nrows (fun i -> match a.(i) with Some x -> Some x | None -> fill_b)))
                | NullColumn n -> (col_name, NullColumn n)
                | DictionaryColumn (a, levels, ordered) ->
                    let fill_i = match replace_val with
                      | VFactor (i, factor_levels, factor_ordered)
                        when factor_levels = levels && factor_ordered = ordered ->
                          Some i
                      | VString s -> Factors.level_index_of levels s
                      | _ -> None
                    in
                    (col_name, DictionaryColumn (Array.init orig_nrows (fun i -> match a.(i) with Some x -> Some x | None -> fill_i), levels, ordered))
              end
            | None -> (col_name, col_data)
          ) all_cols in
          
          let new_schema = List.map (fun (n, c) -> (n, Arrow_table.column_type_of c)) new_columns in
          VDataFrame { arrow_table = { schema = new_schema; columns = new_columns; nrows = orig_nrows; native_handle = None } |> Arrow_table.materialize; group_keys = df.group_keys }
    ))
    env
