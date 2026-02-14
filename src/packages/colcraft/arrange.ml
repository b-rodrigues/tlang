open Ast

let register env =
  Env.add "arrange"
    (make_builtin ~variadic:true 2 (fun args _env ->
      match args with
      | [VDataFrame df; col_val] | [VDataFrame df; col_val; VString "asc"] ->
          (match Utils.extract_column_name col_val with
           | None -> Error.type_error "Function `arrange` expects a $column reference."
           | Some col_name ->
              if not (Arrow_table.has_column df.arrow_table col_name) then
                Error.make_error KeyError (Printf.sprintf "Column `%s` not found in DataFrame." col_name)
              else
                (match Arrow_compute.sort_by_column df.arrow_table col_name true with
                 | Some new_table ->
                   VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
                 | None ->
                   let col = match Arrow_table.get_column df.arrow_table col_name with
                     | Some c -> c | None -> assert false in
                   let col_values = Arrow_bridge.column_to_values col in
                   let nrows = Arrow_table.num_rows df.arrow_table in
                   let indices = Array.init nrows (fun i -> i) in
                   let compare_values a b =
                     match (a, b) with
                     | (VInt x, VInt y) -> compare x y
                     | (VFloat x, VFloat y) -> compare x y
                     | (VString x, VString y) -> String.compare x y
                     | (VBool x, VBool y) -> compare x y
                     | (VNA _, _) -> 1
                     | (_, VNA _) -> -1
                     | _ -> 0
                   in
                   Array.stable_sort (fun i j -> compare_values col_values.(i) col_values.(j)) indices;
                   let new_table = Arrow_compute.sort_by_indices df.arrow_table indices in
                   VDataFrame { arrow_table = new_table; group_keys = df.group_keys }))
      | [VDataFrame df; col_val; VString "desc"] ->
          (match Utils.extract_column_name col_val with
           | None -> Error.type_error "Function `arrange` expects a $column reference."
           | Some col_name ->
              if not (Arrow_table.has_column df.arrow_table col_name) then
                Error.make_error KeyError (Printf.sprintf "Column `%s` not found in DataFrame." col_name)
              else
                (match Arrow_compute.sort_by_column df.arrow_table col_name false with
                 | Some new_table ->
                   VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
                 | None ->
                   let col = match Arrow_table.get_column df.arrow_table col_name with
                     | Some c -> c | None -> assert false in
                   let col_values = Arrow_bridge.column_to_values col in
                   let nrows = Arrow_table.num_rows df.arrow_table in
                   let indices = Array.init nrows (fun i -> i) in
                   let compare_values a b =
                     match (a, b) with
                     | (VInt x, VInt y) -> compare y x
                     | (VFloat x, VFloat y) -> compare y x
                     | (VString x, VString y) -> String.compare y x
                     | (VBool x, VBool y) -> compare y x
                     | (VNA _, _) -> 1
                     | (_, VNA _) -> -1
                     | _ -> 0
                   in
                   Array.stable_sort (fun i j -> compare_values col_values.(i) col_values.(j)) indices;
                   let new_table = Arrow_compute.sort_by_indices df.arrow_table indices in
                   VDataFrame { arrow_table = new_table; group_keys = df.group_keys }))
      | [VDataFrame _; _; VString dir] ->
          Error.value_error (Printf.sprintf "Function `arrange` direction must be \"asc\" or \"desc\", got \"%s\"." dir)
      | [VDataFrame _; _; _] ->
          Error.type_error "Function `arrange` expects a $column reference."
      | [_; _] | [_; _; _] -> Error.type_error "Function `arrange` expects a DataFrame as first argument."
      | _ -> Error.make_error ArityError "Function `arrange` takes 2 or 3 arguments."
     ))
     env
