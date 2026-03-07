open Ast
open Arrow_table

(*
--# Remove rows with missing values
--#
--# drop_na() removes rows from a DataFrame where specified columns have
--# missing values.
--#
--# @name drop_na
--# @param df :: DataFrame The DataFrame.
--# @param ... :: Symbol (Optional) Columns to check for missing values (use $col syntax). 
--#   If none specified, checks all columns.
--# @return :: DataFrame The DataFrame with NA rows removed.
--# @example
--#   drop_na(df)
--#   drop_na(df, $age, $score)
--# @family colcraft
--# @export
*)
let register env =
  Env.add "drop_na"
    (make_builtin ~name:"drop_na" ~variadic:true 1 (fun args _env ->
      match args with
      | VDataFrame df :: cols_variants ->
          let all_names = Arrow_table.column_names df.arrow_table in

          (* Determine which columns to check, validating user-supplied column args *)
          let cols_to_check, parse_err =
            if cols_variants = [] then (all_names, None)
            else
              let parsed = List.filter_map Utils.extract_column_name cols_variants in
              if parsed = [] then
                ([], Some "Function `drop_na` expects column arguments using $col syntax.")
              else (parsed, None)
          in

          (match parse_err with
          | Some msg -> Error.type_error msg
          | None ->

          (* Validate all requested columns exist *)
          let missing = List.filter (fun c -> not (List.mem c all_names)) cols_to_check in
          if missing <> [] then
            Error.make_error KeyError (Printf.sprintf "Function `drop_na`: column(s) not found: %s" (String.concat ", " missing))
          else
          
          let orig_nrows = Arrow_table.num_rows df.arrow_table in
          let keeps = ref [] in
          
          for i = 0 to orig_nrows - 1 do
            let has_na = List.exists (fun col ->
              match Arrow_table.get_column df.arrow_table col with
              | Some (IntColumn a) -> Option.is_none a.(i)
              | Some (FloatColumn a) -> Option.is_none a.(i)
              | Some (StringColumn a) -> Option.is_none a.(i)
              | Some (BoolColumn a) -> Option.is_none a.(i)
              | _ -> true
            ) cols_to_check in
            if not has_na then keeps := i :: !keeps
          done;
          
          let indices = Array.of_list (List.rev !keeps) in
          let new_table = Arrow_compute.sort_by_indices df.arrow_table indices in
          VDataFrame { arrow_table = new_table; group_keys = df.group_keys })
      | _ :: _ -> Error.type_error "Function `drop_na` expects a DataFrame as first argument."
      | _ -> Error.make_error ArityError "Function `drop_na` requires a DataFrame."
    ))
    env
