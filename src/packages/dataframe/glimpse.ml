open Ast

(*
--# Glimpse DataFrame
--#
--# Prints a summary of the DataFrame structure, including dimensions, column names, types, and first few values.
--#
--# @name glimpse
--# @param df :: DataFrame The input DataFrame.
--# @return :: Null
--# @example
--#   glimpse(mtcars)
--# @family to_dataframe
--# @seealso colnames, str
--# @export
*)
let register env =
  Env.add "glimpse"
    (make_builtin ~name:"glimpse" 1 (fun args _env ->
      match args with
      | [VDataFrame { arrow_table; _ }] ->
          let nrows = Arrow_table.num_rows arrow_table in
          let ncols = Arrow_table.num_columns arrow_table in
          let value_columns = Arrow_bridge.table_to_value_columns arrow_table in
          
          Printf.printf "Rows: %d\n" nrows;
          Printf.printf "Columns: %d\n" ncols;
          
          List.iter (fun (name, col) ->
            let col_type = ref "Unknown" in
            (* Determine type from first non-NA value *)
            let found_type = ref false in
            let i = ref 0 in
            let len = Array.length col in
            while not !found_type && !i < len do
              match col.(!i) with
              | VNA _ -> i := !i + 1
              | v -> 
                  col_type := Utils.type_name v;
                  found_type := true
            done;
            (* Fallback if all NA *)
            if not !found_type && len > 0 then col_type := "NA";

            let truncate_str s =
              if String.length s > 25 then
                String.sub s 0 22 ^ "..."
              else
                s
            in
            let example_n = min 10 (Array.length col) in
            let examples = List.init example_n (fun i ->
              truncate_str (Utils.value_to_string col.(i))
            ) in
            let example_str = String.concat ", " examples in
            let suffix = if Array.length col > 10 then ", ..." else "" in
            let final_str = example_str ^ suffix in
            let truncated_final =
              if String.length final_str > 75 then
                String.sub final_str 0 72 ^ "..."
              else
                final_str
            in
            Printf.printf "$ %-13s <%s> %s\n" name !col_type truncated_final
          ) value_columns;
          
          flush stdout;
          (VNA NAGeneric)
      | [VNA _] -> Error.type_error "Function `glimpse` expects a DataFrame, got NA."
      | [_] -> Error.type_error "Function `glimpse` expects a DataFrame."
      | _ -> Error.arity_error_named "glimpse" 1 (List.length args)
    ))
    env
