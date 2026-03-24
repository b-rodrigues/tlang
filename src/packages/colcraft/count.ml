open Ast

let count_impl (named_args : (string option * value) list) _env =
  match named_args with
  | (_, VDataFrame df) :: rest ->
      let key_names = List.filter_map (fun (k, v) -> 
        if k = None then Utils.extract_column_name v else None) rest in
      let name_val = match List.assoc_opt (Some "name") rest with Some (VString s) -> s | _ -> "n" in
      
      let keys = if key_names = [] then df.group_keys else key_names in

      if keys = [] then
        (* Just count rows of the whole df *)
        let n = Arrow_table.num_rows df.arrow_table in
        let arrow_table = Arrow_bridge.table_from_value_columns [(name_val, [|VInt n|])] 1 in
        VDataFrame { arrow_table; group_keys = [] }
      else
        let grouped = Arrow_compute.group_by_optimized df.arrow_table keys in
        let agg_table = Arrow_compute.group_aggregate grouped "count" "" in
        (* group_aggregate returns "n" as column name for "count". Rename if needed. *)
        let final_table = 
          if name_val <> "n" then Arrow_compute.rename_columns agg_table [(name_val, "n")]
          else agg_table in
        VDataFrame { arrow_table = final_table; group_keys = [] }
  | _ :: _ -> Error.type_error "Function `count` expects a DataFrame as first argument."
  | [] -> Error.make_error ArityError "Function `count` requires a DataFrame."

(*
--# Count rows by group
--#
--# Counts rows in a DataFrame, optionally by selected columns or existing group keys.
--#
--# @name count
--# @family colcraft
--# @export
*)
let register env =
  Env.add "count" (make_builtin_named ~name:"count" ~variadic:true 1 count_impl) env
