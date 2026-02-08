open Ast

let register ~eval_call env =
  Env.add "summarize"
    (make_builtin ~variadic:true 1 (fun args env ->
      match args with
      | VDataFrame df :: summary_args ->
          let rec parse_pairs acc = function
            | VString name :: fn :: rest -> parse_pairs ((name, fn) :: acc) rest
            | [] -> Ok (List.rev acc)
            | _ -> Error (make_error TypeError "summarize() expects pairs of (string_name, function)")
          in
          (match parse_pairs [] summary_args with
           | Error e -> e
           | Ok pairs ->
             if pairs = [] then
               make_error ArityError "summarize() requires at least one (name, function) pair"
             else if df.group_keys = [] then
               let result_cols = List.map (fun (name, fn) ->
                 let result = eval_call env fn [(None, Value (VDataFrame df))] in
                 (name, result)
               ) pairs in
               (match List.find_opt (fun (_, v) -> is_error_value v) result_cols with
                | Some (_, e) -> e
                | None ->
                  let columns = List.map (fun (name, v) -> (name, Array.make 1 v)) result_cols in
                  VDataFrame { columns; nrows = 1; group_keys = [] })
             else
               let key_cols = List.map (fun k -> (k, List.assoc k df.columns)) df.group_keys in
               let group_map = Hashtbl.create 16 in
               for i = 0 to df.nrows - 1 do
                 let key_vals = List.map (fun (_, col) -> col.(i)) key_cols in
                 let key_str = String.concat "|" (List.map Utils.value_to_string key_vals) in
                 let existing = try Hashtbl.find group_map key_str with Not_found -> (key_vals, []) in
                 Hashtbl.replace group_map key_str (fst existing, i :: snd existing)
               done;
               let seen = Hashtbl.create 16 in
               let group_order = ref [] in
               for i = 0 to df.nrows - 1 do
                 let key_vals = List.map (fun (_, col) -> col.(i)) key_cols in
                 let key_str = String.concat "|" (List.map Utils.value_to_string key_vals) in
                 if not (Hashtbl.mem seen key_str) then begin
                   Hashtbl.add seen key_str true;
                   group_order := key_str :: !group_order
                 end
               done;
               let group_keys_ordered = List.rev !group_order in
               let n_groups = List.length group_keys_ordered in
               let key_result_cols = List.map (fun k ->
                 let col = Array.init n_groups (fun g_idx ->
                   let key_str = List.nth group_keys_ordered g_idx in
                   let (key_vals, _) = Hashtbl.find group_map key_str in
                   let key_idx = let rec find_idx i = function
                     | [] -> 0 | (kn, _) :: _ when kn = k -> i | _ :: rest -> find_idx (i+1) rest
                   in find_idx 0 key_cols in
                   List.nth key_vals key_idx
                 ) in
                 (k, col)
               ) df.group_keys in
               let had_error = ref None in
               let summary_result_cols = List.map (fun (name, fn) ->
                 let col = Array.init n_groups (fun g_idx ->
                   if !had_error <> None then VNull
                   else begin
                     let key_str = List.nth group_keys_ordered g_idx in
                     let (_, row_indices) = Hashtbl.find group_map key_str in
                     let row_indices = List.rev row_indices in
                     let sub_nrows = List.length row_indices in
                     let sub_columns = List.map (fun (cname, col) ->
                       let sub_col = Array.init sub_nrows (fun j ->
                         col.(List.nth row_indices j)
                       ) in
                       (cname, sub_col)
                     ) df.columns in
                     let sub_df = VDataFrame { columns = sub_columns; nrows = sub_nrows; group_keys = [] } in
                     let result = eval_call env fn [(None, Value sub_df)] in
                     (match result with
                      | VError _ -> had_error := Some result; result
                      | v -> v)
                   end
                 ) in
                 (name, col)
               ) pairs in
               (match !had_error with
                | Some e -> e
                | None ->
                  let all_columns = key_result_cols @ summary_result_cols in
                  VDataFrame { columns = all_columns; nrows = n_groups; group_keys = [] }))
      | _ -> make_error TypeError "summarize() expects a DataFrame as first argument"
    ))
    env
