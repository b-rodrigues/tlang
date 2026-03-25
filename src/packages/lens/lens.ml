open Ast

(*
--# Lens Library
--#
--# Lenses provide a way to get and set values in nested structures.
--# Supports column-based lenses for DataFrames and Dicts.
--#
--# @family lens
*)

let over_val ~eval_call env_ref lens data func =
  match lens with
  | VDict items ->
      (try
        let get_fn = List.assoc "get" items in
        let set_fn = List.assoc "set" items in
        
        let result = eval_call !env_ref get_fn [(None, mk_expr (Value data))] in
        (match result with
         | VError _ as e -> e
         | _ ->
            let transformed = eval_call !env_ref func [(None, mk_expr (Value result))] in
            (match transformed with
             | VError _ as e -> e
             | _ ->
                eval_call !env_ref set_fn [(None, mk_expr (Value data)); (None, mk_expr (Value transformed))]))
      with Not_found -> Error.type_error "Lens missing get/set")
  | _ -> Error.type_error "Lens must be a Dict with get/set functions"

let rec col_lens_get_impl col_name ~eval_call args env =
  match args with
  | [(_, VDataFrame df)] -> 
      (match Arrow_table.get_column df.arrow_table col_name with
       | Some col -> VVector (Arrow_bridge.column_to_values col)
       | None -> VNA NAGeneric)
  | [(_, VDict items)] ->
      (match List.assoc_opt col_name items with
       | Some v -> v
       | None -> VNA NAGeneric)
  | [(_, VVector arr)] ->
      VVector (Array.map (fun v -> col_lens_get_impl col_name ~eval_call [(None, v)] env) arr)
  | [(_, other)] -> 
      Error.type_error (Printf.sprintf "Lens get('%s') cannot be applied to %s" col_name (Utils.type_name other))
  | _ -> Error.arity_error_named ("get_" ^ col_name) 1 (List.length args)

let rec col_lens_set_impl col_name ~eval_call args env =
  match args with
  | [(_, VDataFrame df); (_, val_v)] ->
      let names = Arrow_table.column_names df.arrow_table in
      let nrows = Arrow_table.num_rows df.arrow_table in
      let new_col = match val_v with
        | VVector vals when Array.length vals = nrows -> Arrow_bridge.values_to_column vals
        | VVector vals -> 
            if Array.length vals = 0 then Arrow_table.NullColumn nrows
            else Arrow_bridge.values_to_column (Array.init nrows (fun i -> vals.(i mod Array.length vals)))
        | v -> 
            let vals = Array.make nrows v in
            Arrow_bridge.values_to_column vals
      in
      let columns = List.map (fun name ->
        if name = col_name then (name, new_col)
        else match Arrow_table.get_column df.arrow_table name with
             | Some col -> (name, col)
             | None -> (name, Arrow_table.NullColumn nrows)
      ) names in
      let final_cols = 
        if List.mem col_name names then columns
        else columns @ [(col_name, new_col)]
      in
      VDataFrame { arrow_table = Arrow_table.create final_cols nrows; group_keys = df.group_keys }
  | [(_, VDict items); (_, val_v)] ->
      let new_items = List.map (fun (k, v) -> if k = col_name then (k, val_v) else (k, v)) items in
      let final_items = if List.mem_assoc col_name items then new_items else new_items @ [(col_name, val_v)] in
      VDict final_items
  | [(_, VVector arr); (_, VVector vals)] when Array.length arr = Array.length vals ->
      VVector (Array.map2 (fun data v ->
        col_lens_set_impl col_name ~eval_call [(None, data); (None, v)] env
      ) arr vals)
  | [(_, VVector arr); (_, scalar)] ->
      VVector (Array.map (fun data ->
        col_lens_set_impl col_name ~eval_call [(None, data); (None, scalar)] env
      ) arr)
  | _ -> Error.type_error "Lens set expects (data, value)"

let col_lens_impl ~eval_call args _env =
  match args with
  | [(_, v)] ->
           let col_res = match v with
             | VString s -> Some s
             | VSymbol s when String.length s > 0 && s.[0] = '$' -> 
                 Some (String.sub s 1 (String.length s - 1))
             | VSymbol s -> Some s
             | _ -> None
           in
           (match col_res with
            | Some col_name ->
           let get_fn = VBuiltin {
             b_name = Some ("get_" ^ col_name); b_arity = 1; b_variadic = false;
             b_func = (fun args env_ref -> col_lens_get_impl col_name ~eval_call args !env_ref)
           } in
           let set_fn = VBuiltin {
             b_name = Some ("set_" ^ col_name); b_arity = 2; b_variadic = false;
             b_func = (fun args env_ref -> col_lens_set_impl col_name ~eval_call args !env_ref)
           } in
           VDict [("get", get_fn); ("set", set_fn)]
       | None -> Error.type_error "col_lens expects a column name ($col or \"col\")")
  | _ -> Error.arity_error_named "col_lens" 1 (List.length args)

let over_impl ~eval_call args env =
  match args with
  | [(_, data); (_, lens); (_, func)] ->
      over_val ~eval_call (ref env) lens data func
  | _ -> Error.arity_error_named "over" 3 (List.length args)

let compose_impl ~eval_call args _env =
  match args with
  | [(_, lens1); (_, lens2)] ->
      (match lens1, lens2 with
       | VDict l1, VDict l2 ->
           let has_field l name = List.mem_assoc name l in
           if not (has_field l1 "get" && has_field l1 "set") then
             Error.type_error "compose: First argument is not a valid lens (missing get/set)"
           else if not (has_field l2 "get" && has_field l2 "set") then
             Error.type_error "compose: Second argument is not a valid lens (missing get/set)"
           else begin
             let get1 = List.assoc "get" l1 in
             let get2 = List.assoc "get" l2 in
             let set2 = List.assoc "set" l2 in
             
             let get_composite = VBuiltin {
               b_name = None; b_arity = 1; b_variadic = false;
               b_func = (fun args env_ref ->
                 match args with
                 | [(_, data)] ->
                          let inner = eval_call !env_ref get1 [(None, mk_expr (Value data))] in
                          (match inner with
                           | VError _ as e -> e
                           | _ ->
                               eval_call !env_ref get2 [(None, mk_expr (Value inner))])
                 | _ -> Error.arity_error_named "get" 1 (List.length args))
             } in
             
             let set_composite = VBuiltin {
               b_name = None; b_arity = 2; b_variadic = false;
               b_func = (fun args env_ref ->
                 match args with
                 | [(_, data); (_, val_v)] ->
                          let setter_lambda = VLambda {
                            params = ["inner"]; param_types = [None]; return_type = None; generic_params = []; variadic = false;
                            body = mk_expr (Call { fn = mk_expr (Value set2); args = [(None, mk_expr (Var "inner")); (None, mk_expr (Value val_v))] });
                            env = Some !env_ref;
                          } in
                          over_val ~eval_call env_ref lens1 data setter_lambda
                 | _ -> Error.arity_error_named "set" 2 (List.length args))
             } in
             VDict [("get", get_composite); ("set", set_composite)]
           end
       | _ -> Error.type_error "compose expects two Lenses")
  | _ -> Error.arity_error_named "compose" 2 (List.length args)

let set_impl ~eval_call args env =
  match args with
  | [(_, data); (_, lens); (_, val_v)] ->
      (match lens with
       | VDict items ->
           (match List.assoc_opt "set" items with
            | Some set_fn -> eval_call env set_fn [(None, mk_expr (Value data)); (None, mk_expr (Value val_v))]
            | None -> Error.type_error "Lens missing set function")
       | _ -> Error.type_error "set: second argument must be a Lens")
 | _ -> Error.arity_error_named "set" 3 (List.length args)

let modify_impl ~eval_call args env =
  match args with
  | (_, data) :: rest ->
      let rec apply_mods current_data mods =
        match mods with
        | [] -> current_data
        | (_, lens) :: (_, func) :: tail ->
            let result = over_val ~eval_call (ref env) lens current_data func in
            (match result with
             | VError _ as e -> e
             | _ -> apply_mods result tail)
        | _ -> Error.type_error "modify expects (data, lens1, func1, lens2, func2, ...)"
      in
      apply_mods data rest
  | [] -> Error.arity_error_named "modify" 1 0

let node_lens_impl ~eval_call:_ args _env =
  match args with
  | [(_, VString node_name)] ->
      let get_fn = VBuiltin {
        b_name = Some ("node_get_" ^ node_name); b_arity = 1; b_variadic = false;
        b_func = (fun args _env_ref ->
          match args with
          | [(_, VPipeline p)] ->
              (match List.assoc_opt node_name p.p_nodes with
               | Some v -> v
               | None -> VNA NAGeneric)
          | _ -> Error.type_error "node_lens get expects a Pipeline")
      } in
      let set_fn = VBuiltin {
        b_name = Some ("node_set_" ^ node_name); b_arity = 2; b_variadic = false;
        b_func = (fun args _env_ref ->
          match args with
          | [(_, VPipeline p); (_, val_v)] ->
              let new_nodes = List.map (fun (n, v) -> if n = node_name then (n, val_v) else (n, v)) p.p_nodes in
              let final_nodes = if List.mem_assoc node_name p.p_nodes then new_nodes else new_nodes @ [(node_name, val_v)] in
              VPipeline { p with p_nodes = final_nodes }
          | _ -> Error.type_error "node_lens set expects (Pipeline, value)")
      } in
      VDict [("get", get_fn); ("set", set_fn)]
  | _ -> Error.type_error "node_lens expects a node name (String)"

let env_var_lens_impl ~eval_call:_ args _env =
  match args with
  | [(_, VString node_name); (_, VString var_name)] ->
      let get_fn = VBuiltin {
        b_name = Some ("env_var_get_" ^ node_name ^ "_" ^ var_name); b_arity = 1; b_variadic = false;
        b_func = (fun args _env_ref ->
          match args with
          | [(_, VPipeline p)] ->
              (match List.assoc_opt node_name p.p_env_vars with
               | Some vars ->
                   (match List.assoc_opt var_name vars with
                    | Some v -> v
                    | None -> VNA NAGeneric)
               | None -> VNA NAGeneric)
          | _ -> Error.type_error "env_var_lens get expects a Pipeline")
      } in
      let set_fn = VBuiltin {
        b_name = Some ("env_var_set_" ^ node_name ^ "_" ^ var_name); b_arity = 2; b_variadic = false;
        b_func = (fun args _env_ref ->
          match args with
          | [(_, VPipeline p); (_, val_v)] ->
              let vars = match List.assoc_opt node_name p.p_env_vars with Some v -> v | None -> [] in
              let new_vars = List.map (fun (k, v) -> if k = var_name then (k, val_v) else (k, v)) vars in
              let final_vars = if List.mem_assoc var_name vars then new_vars else new_vars @ [(var_name, val_v)] in
              let new_env_vars = List.map (fun (n, v) -> if n = node_name then (n, final_vars) else (n, v)) p.p_env_vars in
              let final_env_vars = if List.mem_assoc node_name p.p_env_vars then new_env_vars else new_env_vars @ [(node_name, final_vars)] in
              VPipeline { p with p_env_vars = final_env_vars }
          | _ -> Error.type_error "env_var_lens set expects (Pipeline, value)")
      } in
      VDict [("get", get_fn); ("set", set_fn)]
  | _ -> Error.type_error "env_var_lens expects (node_name, var_name)"

let register ~eval_call env =
  let make_l_builtin name arity f env =
    Env.add name (VBuiltin { b_name = Some name; b_arity = arity; b_variadic = false; b_func = (fun args env_ref -> f ~eval_call args !env_ref) }) env
  in
  env
  |> make_l_builtin "col_lens" 1 col_lens_impl
  |> make_l_builtin "over" 3 over_impl
  |> make_l_builtin "compose" 2 compose_impl
  |> make_l_builtin "set" 3 set_impl
  |> make_l_builtin "modify" 1 modify_impl
  |> make_l_builtin "node_lens" 1 node_lens_impl
  |> make_l_builtin "env_var_lens" 2 env_var_lens_impl
