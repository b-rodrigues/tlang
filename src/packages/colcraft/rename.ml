open Ast

let rename_impl (named_args : (string option * value) list) _env =
  match named_args with
  | (_, VDataFrame df) :: rest ->
      let mapping = List.filter_map (function
        | (Some new_name, v) ->
            (match Utils.extract_column_name v with
             | Some old_name -> Some (new_name, old_name)
             | None -> None (* Skip invalid renames *))
        | (None, _) ->
            (* Check if it's a VList from a matcher *)
            None
      ) rest in
      if mapping = [] then VDataFrame df
      else
        let new_table = Arrow_compute.rename_columns df.arrow_table mapping in
        (* Update group keys if any were renamed *)
        let new_group_keys = List.map (fun k ->
          match List.assoc_opt k (List.map (fun (n, o) -> (o, n)) mapping) with
          | Some new_k -> new_k
          | None -> k
        ) df.group_keys in
        VDataFrame { arrow_table = new_table; group_keys = new_group_keys }
  | _ :: _ -> Error.type_error "Function `rename` expects a DataFrame as first argument."
  | [] -> Error.make_error ArityError "Function `rename` requires a DataFrame and at least one new_name = $old_name pair."

let register env =
  Env.add "rename" (make_builtin_named ~name:"rename" ~variadic:true 1 rename_impl) env
