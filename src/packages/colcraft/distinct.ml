open Ast

let distinct_impl (named_args : (string option * value) list) _env =
  match named_args with
  | (_, VDataFrame df) :: rest ->
      let all_names = Arrow_table.column_names df.arrow_table in
      let key_names = List.filter_map (fun (k, v) -> 
        if k = None then Utils.extract_column_name v else None) rest in
      let keep_all = match List.assoc_opt (Some ".keep_all") rest with Some (VBool b) -> b | _ -> false in
      
      let keys = if key_names = [] then all_names else key_names in
      let nrows = Arrow_table.num_rows df.arrow_table in
      
      (* Get key column values for hash calculation *)
      let key_col_values = List.map (fun k ->
        match Arrow_table.get_column df.arrow_table k with
        | Some col -> Arrow_bridge.column_to_values col
        | None -> Array.make nrows VNull
      ) keys in
      
      let seen = Hashtbl.create nrows in
      let row_indices = ref [] in
      for i = 0 to nrows - 1 do
        let key_vals = List.map (fun col -> col.(i)) key_col_values in
        if not (Hashtbl.mem seen key_vals) then begin
          Hashtbl.add seen key_vals true;
          row_indices := i :: !row_indices
        end
      done;
      
      let unique_indices = List.rev !row_indices in
      let final_names = if keep_all || key_names = [] then all_names else key_names in
      
      let sub_table = Arrow_compute.take_rows df.arrow_table unique_indices in
      let project_table = Arrow_compute.project sub_table final_names in
      
      VDataFrame { df with arrow_table = project_table }
  | _ :: _ -> Error.type_error "Function `distinct` expects a DataFrame as first argument."
  | [] -> Error.make_error ArityError "Function `distinct` requires a DataFrame."

let register env =
  Env.add "distinct" (make_builtin_named ~name:"distinct" ~variadic:true 1 distinct_impl) env
