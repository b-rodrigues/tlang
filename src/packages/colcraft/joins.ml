open Ast

type join_kind =
  | Left
  | Inner
  | Full
  | Semi
  | Anti

let positional_args named_args =
  List.filter_map (function None, v -> Some v | _ -> None) named_args

let find_named_arg name named_args =
  List.find_map (function Some n, v when n = name -> Some v | _ -> None) named_args

let string_list_of_value = function
  | VString s -> Ok [s]
  | VVector arr ->
      Array.fold_right (fun value acc ->
        match value, acc with
        | VString s, Ok values -> Ok (s :: values)
        | VNA _, Ok _ -> Error (Error.type_error "Join keys must be strings, not NA.")
        | _, Ok _ -> Error (Error.type_error "Join keys must be strings.")
        | _, Error err -> Error err
      ) arr (Ok [])
  | VList items ->
      List.fold_right (fun (_, value) acc ->
        match value, acc with
        | VString s, Ok values -> Ok (s :: values)
        | VNA _, Ok _ -> Error (Error.type_error "Join keys must be strings, not NA.")
        | _, Ok _ -> Error (Error.type_error "Join keys must be strings.")
        | _, Error err -> Error err
      ) items (Ok [])
  | _ -> Error (Error.type_error "Join keys must be a string, List[String], or Vector[String].")

let common_columns left right =
  let right_names = Arrow_table.column_names right in
  Arrow_table.column_names left
  |> List.filter (fun name -> List.mem name right_names)

let parse_by named_args left right =
  let positional = positional_args named_args in
  let explicit_by =
    match find_named_arg "by" named_args with
    | Some value -> Some value
    | None ->
        (match positional with
         | [_; _; value] -> Some value
         | _ -> None)
  in
  let by_result =
    match explicit_by with
    | Some value -> string_list_of_value value
    | None ->
        let inferred = common_columns left right in
        if inferred = [] then
          Error
            (Error.value_error
               "Join requires at least one shared column, or an explicit `by` argument.")
        else
          Ok inferred
  in
  match by_result with
  | Error err -> Error err
  | Ok by ->
      let missing_left =
        List.filter (fun name -> not (Arrow_table.has_column left name)) by
      in
      let missing_right =
        List.filter (fun name -> not (Arrow_table.has_column right name)) by
      in
      if missing_left <> [] then
        Error
          (Error.make_error KeyError
             (Printf.sprintf
                "Join key(s) not found in left DataFrame: %s."
                (String.concat ", " missing_left)))
      else if missing_right <> [] then
        Error
          (Error.make_error KeyError
             (Printf.sprintf
                "Join key(s) not found in right DataFrame: %s."
                (String.concat ", " missing_right)))
      else
        Ok by

let table_rows table =
  let nrows = Arrow_table.num_rows table in
  Array.init nrows (fun idx -> Arrow_bridge.row_to_dict table idx)

let assoc_value row name =
  match List.assoc_opt name row with
  | Some value -> value
  | None -> VNA NAGeneric

let key_of_row by row =
  by
  |> List.map (fun name -> Ast.Utils.value_to_string (assoc_value row name))
  |> String.concat "\x1f"

let make_name_unique used base =
  let rec loop idx =
    let candidate =
      if idx = 0 then base else Printf.sprintf "%s_%d" base idx
    in
    if List.mem candidate !used then
      loop (idx + 1)
    else begin
      used := !used @ [candidate];
      candidate
    end
  in
  loop 0

let right_projection left_names right_names by =
  let used = ref left_names in
  List.fold_left (fun acc name ->
    if List.mem name by then
      acc
    else
      let base =
        if List.mem name left_names then name ^ "_y" else name
      in
      let output_name = make_name_unique used base in
      acc @ [(name, output_name)]
  ) [] right_names

let make_empty_row columns =
  List.map (fun name -> (name, VNA NAGeneric)) columns

let merge_left_right ~left_names ~right_projection ~by left_row right_row_opt =
  let right_lookup name =
    match right_row_opt with
    | Some row -> assoc_value row name
    | None -> VNA NAGeneric
  in
  let left_pairs =
    List.map (fun name -> (name, assoc_value left_row name)) left_names
  in
  let right_pairs =
    List.map (fun (source_name, output_name) -> (output_name, right_lookup source_name)) right_projection
  in
  let key_backfill =
    match right_row_opt with
    | Some row ->
        List.map (fun name -> (name, assoc_value row name)) by
    | None -> []
  in
  left_pairs
  |> List.map (fun (name, value) ->
         if value = VNA NAGeneric && List.mem_assoc name key_backfill then
           (name, List.assoc name key_backfill)
         else
           (name, value))
  |> fun pairs -> pairs @ right_pairs

let rows_to_dataframe column_order rows =
  let nrows = List.length rows in
  let columns =
    List.map (fun name ->
      let values =
        Array.of_list
          (List.map (fun row ->
               match List.assoc_opt name row with
               | Some value -> value
               | None -> VNA NAGeneric) rows)
      in
      (name, values)
    ) column_order
  in
  VDataFrame { arrow_table = Arrow_bridge.table_from_value_columns columns nrows; group_keys = [] }

let join_impl kind named_args _env =
  match positional_args named_args with
  | [VDataFrame left; VDataFrame right]
  | [VDataFrame left; VDataFrame right; _] ->
      (match parse_by named_args left.arrow_table right.arrow_table with
       | Error err -> err
       | Ok by ->
           let left_names = Arrow_table.column_names left.arrow_table in
           let right_names = Arrow_table.column_names right.arrow_table in
           let right_projection = right_projection left_names right_names by in
           let output_columns =
             left_names @ List.map snd right_projection
           in
           let left_rows = table_rows left.arrow_table in
           let right_rows = table_rows right.arrow_table in
           let right_matches = Array.make (Array.length right_rows) false in
           let right_index = Hashtbl.create 32 in
           Array.iteri (fun idx row ->
             let key = key_of_row by row in
             let existing =
               match Hashtbl.find_opt right_index key with
               | Some indices -> indices
               | None -> []
             in
             Hashtbl.replace right_index key (existing @ [idx])
           ) right_rows;
           let joined_rows = ref [] in
           Array.iter (fun left_row ->
             let key = key_of_row by left_row in
             let matches =
               match Hashtbl.find_opt right_index key with
               | Some indices -> indices
               | None -> []
             in
             match kind, matches with
             | Anti, [] ->
                 joined_rows := !joined_rows @ [List.map (fun name -> (name, assoc_value left_row name)) left_names]
             | Anti, _ -> ()
             | Semi, [] -> ()
             | Semi, _ ->
                 joined_rows := !joined_rows @ [List.map (fun name -> (name, assoc_value left_row name)) left_names]
             | (Left | Full), [] ->
                 joined_rows :=
                   !joined_rows @ [merge_left_right ~left_names ~right_projection ~by left_row None]
             | Inner, [] -> ()
             | _, indices ->
                 List.iter (fun idx ->
                   right_matches.(idx) <- true;
                   joined_rows :=
                     !joined_rows
                     @ [merge_left_right ~left_names ~right_projection ~by left_row (Some right_rows.(idx))]
                 ) indices
           ) left_rows;
           let joined_rows =
             match kind with
             | Full ->
                 let unmatched_right_rows =
                   Array.to_list
                     (Array.mapi (fun idx row -> (idx, row)) right_rows)
                   |> List.filter_map (fun (idx, row) ->
                        if right_matches.(idx) then
                          None
                        else
                          let left_stub =
                            List.map (fun name ->
                              if List.mem name by then
                                (name, assoc_value row name)
                              else
                                (name, VNA NAGeneric)) left_names
                          in
                          Some (merge_left_right ~left_names ~right_projection ~by left_stub (Some row)))
                 in
                 !joined_rows @ unmatched_right_rows
             | _ -> !joined_rows
           in
           rows_to_dataframe output_columns joined_rows)
  | _ :: _ ->
      Error.type_error "Join functions expect two DataFrames as the first positional arguments."
  | [] ->
      Error.make_error ArityError "Join functions require at least two DataFrames."

let bind_rows_impl args _env =
  match args with
  | [] ->
      Error.make_error ArityError "Function `bind_rows` requires at least one DataFrame."
  | _ ->
      let dataframes =
        List.fold_right (fun value acc ->
          match value, acc with
          | VDataFrame df, Ok dfs -> Ok (df :: dfs)
          | _, Ok _ -> Error (Error.type_error "Function `bind_rows` expects only DataFrame arguments.")
          | _, Error err -> Error err
        ) args (Ok [])
      in
      (match dataframes with
       | Error err -> err
       | Ok dfs ->
           let column_order =
             List.fold_left (fun acc df ->
               List.fold_left (fun inner name ->
                 if List.mem name inner then inner else inner @ [name]
               ) acc (Arrow_table.column_names df.arrow_table)
             ) [] dfs
           in
           let rows =
             List.concat_map (fun df ->
               Array.to_list (table_rows df.arrow_table)
             ) dfs
           in
           rows_to_dataframe column_order rows)

let bind_cols_impl args _env =
  match args with
  | [] ->
      Error.make_error ArityError "Function `bind_cols` requires at least one DataFrame."
  | _ ->
      let dataframes =
        List.fold_right (fun value acc ->
          match value, acc with
          | VDataFrame df, Ok dfs -> Ok (df :: dfs)
          | _, Ok _ -> Error (Error.type_error "Function `bind_cols` expects only DataFrame arguments.")
          | _, Error err -> Error err
        ) args (Ok [])
      in
      (match dataframes with
       | Error err -> err
       | Ok dfs ->
           let row_counts =
             List.map (fun df -> Arrow_table.num_rows df.arrow_table) dfs
           in
           let expected_rows =
             match row_counts with
             | n :: _ -> n
             | [] -> 0
           in
           if List.exists ((<>) expected_rows) row_counts then
             Error.value_error "Function `bind_cols` requires all DataFrames to have the same number of rows."
           else
             let used_names = ref [] in
             let columns =
               List.concat_map (fun df ->
                 Arrow_bridge.table_to_value_columns df.arrow_table
                 |> List.map (fun (name, values) ->
                      let output_name = make_name_unique used_names name in
                      (output_name, values))
               ) dfs
             in
             VDataFrame { arrow_table = Arrow_bridge.table_from_value_columns columns expected_rows; group_keys = [] })

let register env =
  let env =
    Env.add "left_join"
      (make_builtin_named ~name:"left_join" ~variadic:true 2 (join_impl Left))
      env
  in
  let env =
    Env.add "inner_join"
      (make_builtin_named ~name:"inner_join" ~variadic:true 2 (join_impl Inner))
      env
  in
  let env =
    Env.add "full_join"
      (make_builtin_named ~name:"full_join" ~variadic:true 2 (join_impl Full))
      env
  in
  let env =
    Env.add "semi_join"
      (make_builtin_named ~name:"semi_join" ~variadic:true 2 (join_impl Semi))
      env
  in
  let env =
    Env.add "anti_join"
      (make_builtin_named ~name:"anti_join" ~variadic:true 2 (join_impl Anti))
      env
  in
  let env =
    Env.add "bind_rows"
      (make_builtin ~name:"bind_rows" ~variadic:true 1 bind_rows_impl)
      env
  in
  let env =
    Env.add "bind_cols"
      (make_builtin ~name:"bind_cols" ~variadic:true 1 bind_cols_impl)
      env
  in
  env
