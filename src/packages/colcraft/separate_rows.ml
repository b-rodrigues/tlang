open Ast
open Arrow_table

let separate_rows_impl (named_args : (string option * value) list) _env =
  match named_args with
  | (_, VDataFrame df) :: rest ->
      let col_to_sep = match List.filter (fun (k, _) -> k = None) rest with
        | [(_, v)] -> Utils.extract_column_name v
        | _ -> None
      in
      let sep = match List.assoc_opt (Some "sep") rest with Some (VString s) -> s | _ -> "[^A-Za-z0-9]+" in

      (match col_to_sep with
       | None -> Error.make_error ArityError "separate_rows expects a column to separate ($col)."
       | Some col_name ->
           match Arrow_table.get_column df.arrow_table col_name with
           | Some (StringColumn data) ->
               let re = Str.regexp sep in
               let tokens = Array.map (function 
                 | Some s -> Str.split re s
                 | None -> [""]
               ) data in
               
               let final_nrows = Array.fold_left (fun acc t -> acc + List.length t) 0 tokens in
               
               let expansion_indices = Array.make final_nrows 0 in
               let sep_values = Array.make final_nrows (VNA NAGeneric) in
               let curr = ref 0 in
               Array.iteri (fun i t_list ->
                 List.iter (fun t ->
                   expansion_indices.(!curr) <- i;
                   sep_values.(!curr) <- VString t;
                   incr curr
                 ) t_list
               ) tokens;
               
               let new_columns = List.map (fun (name, _) ->
                 if name = col_name then
                   (name, Arrow_bridge.values_to_column sep_values)
                 else
                   match Arrow_table.get_column df.arrow_table name with
                   | Some col -> (name, Arrow_table.take_col col expansion_indices final_nrows)
                   | None -> (name, Arrow_table.NAColumn final_nrows)
               ) df.arrow_table.schema in
               
               VDataFrame { df with arrow_table = { df.arrow_table with columns = new_columns; nrows = final_nrows; native_handle = None } }
           | _ -> Error.type_error (Printf.sprintf "Column `%s` is not a String column." col_name))
  | _ :: _ -> Error.type_error "Function `separate_rows` expects a DataFrame as first argument."
  | [] -> Error.make_error ArityError "Function `separate_rows` requires a DataFrame."

(*
--# Split delimited values into rows
--#
--# Expands delimited string values into multiple rows while repeating the remaining columns.
--#
--# @name separate_rows
--# @family colcraft
--# @export
*)
let register env =
  Env.add "separate_rows" (make_builtin_named ~name:"separate_rows" ~variadic:true 1 separate_rows_impl) env
