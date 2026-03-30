open Ast

(*
--# Lens Library
--#
--# Lenses provide a way to get and set values in nested structures.
--# Supports column-based lenses for DataFrames and Dicts.
--#
--# @name lens
--# @family lens
--# @export
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
  | [(_, VList items)] ->
      VList (List.map (fun (name, v) -> (name, col_lens_get_impl col_name ~eval_call [(None, v)] env)) items)
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
  | [(_, VList items); (_, VList vals)] when List.length items = List.length vals ->
      VList (List.map2 (fun (name, data) (_, v) ->
        (name, col_lens_set_impl col_name ~eval_call [(None, data); (None, v)] env)
      ) items vals)
  | [(_, VList items); (_, scalar)] ->
      VList (List.map (fun (name, data) ->
        (name, col_lens_set_impl col_name ~eval_call [(None, data); (None, scalar)] env)
      ) items)
  | _ -> Error.type_error "Lens set expects (data, value)"

(*
--# Create a Column Lens
--#
--# Targets a column in a DataFrame or a key in a Dictionary.
--#
--# @name col_lens
--# @param name :: String The column or key name.
--# @return :: Lens A lens for the specified column/key.
--# @family lens
--# @export
*)
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

let idx_lens_get_impl i ~eval_call:_ args _env =
  match args with
  | [(_, VList items)] ->
      let len = List.length items in
      if i < 0 || i >= len then Error.index_error i len
      else let (_, v) = List.nth items i in v
  | [(_, VVector arr)] ->
      let len = Array.length arr in
      if i < 0 || i >= len then Error.index_error i len
      else arr.(i)
  | [(_, other)] -> Error.type_error (Printf.sprintf "idx_lens get expects a List or Vector, got %s" (Utils.type_name other))
  | _ -> Error.arity_error_named "idx_lens.get" 1 (List.length args)

let idx_lens_set_impl i ~eval_call:_ args _env =
  match args with
  | [(_, VList items); (_, val_v)] ->
      let len = List.length items in
      if i < 0 || i >= len then Error.index_error i len
      else
        let new_items = List.mapi (fun j (name, v) -> if j = i then (name, val_v) else (name, v)) items in
        VList new_items
  | [(_, VVector arr); (_, val_v)] ->
      let len = Array.length arr in
      if i < 0 || i >= len then Error.index_error i len
      else
        let new_arr = Array.copy arr in
        new_arr.(i) <- val_v;
        VVector new_arr
  | [(_, other); _] -> Error.type_error (Printf.sprintf "idx_lens set expects a List or Vector, got %s" (Utils.type_name other))
  | _ -> Error.arity_error_named "idx_lens.set" 2 (List.length args)

(*
--# Index Lens
--#
--# Targets an element in a List or Vector by its 0-based index.
--#
--# @name idx_lens
--# @param i :: Int The index to target.
--# @return :: Lens A lens for the specified index.
--# @family lens
--# @export
*)
let idx_lens_impl ~eval_call args _env =
  match args with
  | [(_, VInt i)] ->
      let get_fn = VBuiltin {
        b_name = Some (Printf.sprintf "idx_get_%d" i); b_arity = 1; b_variadic = false;
        b_func = (fun args env_ref -> idx_lens_get_impl i ~eval_call args !env_ref)
      } in
      let set_fn = VBuiltin {
        b_name = Some (Printf.sprintf "idx_set_%d" i); b_arity = 2; b_variadic = false;
        b_func = (fun args env_ref -> idx_lens_set_impl i ~eval_call args !env_ref)
      } in
      VDict [("get", get_fn); ("set", set_fn)]
  | [(_, VNA _)] -> Error.type_error "idx_lens: index cannot be NA"
  | [(_, other)] -> Error.type_error (Printf.sprintf "idx_lens expects an integer index, got %s" (Utils.type_name other))
  | _ -> Error.arity_error_named "idx_lens" 1 (List.length args)

let row_lens_get_impl i ~eval_call:_ args _env =
  match args with
  | [(_, VDataFrame df)] ->
      let nrows = Arrow_table.num_rows df.arrow_table in
      if i < 0 || i >= nrows then Error.index_error i nrows
      else
        let dict = Arrow_bridge.row_to_dict df.arrow_table i in
        VDict dict
  | [(_, other)] -> Error.type_error (Printf.sprintf "row_lens get expects a DataFrame, got %s" (Utils.type_name other))
  | _ -> Error.arity_error_named "row_get" 1 (List.length args)

let row_lens_set_impl i ~eval_call:_ args _env =
  match args with
  | [(_, VDataFrame df); (_, VDict row_items)] ->
      let nrows = Arrow_table.num_rows df.arrow_table in
      if i < 0 || i >= nrows then Error.index_error i nrows
      else
        let names = Arrow_table.column_names df.arrow_table in
        let updated_cols = List.map (fun name ->
          let col = match Arrow_table.get_column df.arrow_table name with
            | Some c -> c
            | None -> Arrow_table.NullColumn nrows
          in
          let vals = Arrow_bridge.column_to_values col in
          let new_val = match List.assoc_opt name row_items with
            | Some v -> v
            | None -> VNA NAGeneric
          in
          if i < Array.length vals then vals.(i) <- new_val;
          (name, Arrow_bridge.values_to_column vals)
        ) names in
        (* Add new columns for keys present in the row Dict but missing from the DataFrame *)
        let names_tbl = Hashtbl.create (List.length names) in
        List.iter (fun n -> Hashtbl.replace names_tbl n ()) names;
        let extra_cols = List.filter_map (fun (name, v) ->
          if Hashtbl.mem names_tbl name then None
          else
            let vals = Array.make nrows (VNA NAGeneric) in
            vals.(i) <- v;
            Some (name, Arrow_bridge.values_to_column vals)
        ) row_items in
        let all_cols = updated_cols @ extra_cols in
        VDataFrame { df with arrow_table = Arrow_table.create all_cols nrows }
  | [(_, VDataFrame _); (_, other)] -> Error.type_error (Printf.sprintf "row_lens set expects a Dict for the row data, got %s" (Utils.type_name other))
  | [(_, other); _] -> Error.type_error (Printf.sprintf "row_lens set expects a DataFrame, got %s" (Utils.type_name other))
  | _ -> Error.arity_error_named "row_set" 2 (List.length args)

(*
--# Row Lens
--#
--# Targets a specific row in a DataFrame by its 0-based index.
--#
--# @name row_lens
--# @param i :: Int The row index.
--# @return :: Lens A lens for the specified row.
--# @family lens
--# @export
*)
let row_lens_impl ~eval_call args _env =
  match args with
  | [(_, VInt i)] ->
      let get_fn = VBuiltin {
        b_name = Some (Printf.sprintf "row_get_%d" i); b_arity = 1; b_variadic = false;
        b_func = (fun args env_ref -> row_lens_get_impl i ~eval_call args !env_ref)
      } in
      let set_fn = VBuiltin {
        b_name = Some (Printf.sprintf "row_set_%d" i); b_arity = 2; b_variadic = false;
        b_func = (fun args env_ref -> row_lens_set_impl i ~eval_call args !env_ref)
      } in
      VDict [("get", get_fn); ("set", set_fn)]
  | [(_, VNA _)] -> Error.type_error "row_lens: index cannot be NA"
  | [(_, other)] -> Error.type_error (Printf.sprintf "row_lens expects an integer index, got %s" (Utils.type_name other))
  | _ -> Error.arity_error_named "row_lens" 1 (List.length args)

let filter_lens_get_impl p ~eval_call args env =
  let eval_pred v =
    match eval_call env p [(None, mk_expr (Value v))] with
    | VBool b -> Ok b
    | VError _ as e -> Error e
    | other ->
        Error (Error.type_error
          (Printf.sprintf "filter_lens predicate must return Bool, got %s"
            (Utils.type_name other)))
  in
  match args with
  | [(_, VList items)] ->
      let rec aux acc = function
        | [] -> Ok (List.rev acc)
        | (name, v) :: rest ->
            (match eval_pred v with
             | Ok true -> aux ((name, v) :: acc) rest
             | Ok false -> aux acc rest
             | Error e -> Error e)
      in
      (match aux [] items with
       | Ok filtered -> VList filtered
       | Error e -> e)
  | [(_, VVector arr)] ->
      let rec aux acc = function
        | [] -> Ok (List.rev acc)
        | v :: rest ->
            (match eval_pred v with
             | Ok true -> aux (v :: acc) rest
             | Ok false -> aux acc rest
             | Error e -> Error e)
      in
      (match aux [] (Array.to_list arr) with
       | Ok filtered -> VVector (Array.of_list filtered)
       | Error e -> e)
  | [(_, VDataFrame df)] ->
      let nrows = Arrow_table.num_rows df.arrow_table in
      let keep = Array.make nrows false in
      let rec aux i =
        if i >= nrows then Ok ()
        else
          let row_dict = VDict (Arrow_bridge.row_to_dict df.arrow_table i) in
          match eval_pred row_dict with
          | Ok b -> keep.(i) <- b; aux (i + 1)
          | Error e -> Error e
      in
      (match aux 0 with
       | Error e -> e
       | Ok () ->
           let new_table = Arrow_compute.filter df.arrow_table keep in
           VDataFrame { df with arrow_table = new_table })
  | [(_, other)] ->
      Error.type_error (Printf.sprintf "filter_lens get expects a Collection, got %s"
        (Utils.type_name other))
  | _ -> Error.arity_error_named "filter_lens.get" 1 (List.length args)

let filter_lens_set_impl p ~eval_call args env =
  let eval_pred v =
    match eval_call env p [(None, mk_expr (Value v))] with
    | VBool b -> Ok b
    | VError _ as e -> Error e
    | other ->
        Error (Error.type_error
          (Printf.sprintf "filter_lens predicate must return Bool, got %s"
            (Utils.type_name other)))
  in
  (* Build predicate mask using an indexed value accessor. Returns (mask, match_count) or error. *)
  let build_mask n get_v =
    let mask = Array.make n false in
    let rec aux i count =
      if i >= n then Ok (mask, count)
      else
        match eval_pred (get_v i) with
        | Ok b ->
            if b then mask.(i) <- true;
            aux (i + 1) (if b then count + 1 else count)
        | Error e -> Error e
    in
    aux 0 0
  in
  match args with
  | [(_, VList items); (_, replacement)] ->
      let arr = Array.of_list items in
      (match build_mask (Array.length arr) (fun i -> snd arr.(i)) with
       | Error e -> e
       | Ok (mask, match_count) ->
           (match replacement with
            | VList repl_items ->
                let repl_len = List.length repl_items in
                if repl_len <> match_count then
                  Error.type_error
                    (Printf.sprintf
                       "filter_lens set on List: replacement has %d elements but %d were matched"
                       repl_len match_count)
                else
                  let repl_arr = Array.of_list (List.map snd repl_items) in
                  let repl_idx = ref 0 in
                  let new_items = Array.to_list (Array.mapi (fun i (name, v) ->
                    if mask.(i) then
                      let new_v = repl_arr.(!repl_idx) in
                      incr repl_idx; (name, new_v)
                    else (name, v)
                  ) arr) in
                  VList new_items
            | val_v ->
                (* scalar broadcast: replace every matched element with val_v *)
                VList (Array.to_list (Array.mapi (fun i (name, v) ->
                  if mask.(i) then (name, val_v) else (name, v)
                ) arr))))
  | [(_, VVector arr); (_, replacement)] ->
      (match build_mask (Array.length arr) (fun i -> arr.(i)) with
       | Error e -> e
       | Ok (mask, match_count) ->
           (match replacement with
            | VVector repl_arr ->
                let repl_len = Array.length repl_arr in
                if repl_len <> match_count then
                  Error.type_error
                    (Printf.sprintf
                       "filter_lens set on Vector: replacement has %d elements but %d were matched"
                       repl_len match_count)
                else
                  let repl_idx = ref 0 in
                  let new_arr = Array.mapi (fun i v ->
                    if mask.(i) then begin
                      let new_v = repl_arr.(!repl_idx) in
                      incr repl_idx; new_v
                    end else v
                  ) arr in
                  VVector new_arr
            | val_v ->
                (* scalar broadcast *)
                VVector (Array.mapi (fun i v -> if mask.(i) then val_v else v) arr)))
  | [(_, VDataFrame df); (_, replacement)] ->
      let nrows = Arrow_table.num_rows df.arrow_table in
      (match build_mask nrows
               (fun i -> VDict (Arrow_bridge.row_to_dict df.arrow_table i)) with
       | Error e -> e
       | Ok (mask, match_count) ->
           let names = Arrow_table.column_names df.arrow_table in
           (match replacement with
            | VDataFrame df_repl ->
                let repl_nrows = Arrow_table.num_rows df_repl.arrow_table in
                if repl_nrows <> match_count then
                  Error.type_error
                    (Printf.sprintf
                       "filter_lens set on DataFrame: replacement has %d rows but %d were matched"
                       repl_nrows match_count)
                else
                  let updated_cols = List.map (fun name ->
                    let col = match Arrow_table.get_column df.arrow_table name with
                      | Some c -> c | None -> Arrow_table.NullColumn nrows
                    in
                    let vals = Arrow_bridge.column_to_values col in
                    let repl_col = match Arrow_table.get_column df_repl.arrow_table name with
                      | Some c -> c | None -> Arrow_table.NullColumn match_count
                    in
                    let repl_vals = Arrow_bridge.column_to_values repl_col in
                    let repl_idx = ref 0 in
                    for i = 0 to nrows - 1 do
                      if mask.(i) then begin
                        vals.(i) <- repl_vals.(!repl_idx);
                        incr repl_idx
                      end
                    done;
                    (name, Arrow_bridge.values_to_column vals)
                  ) names in
                  VDataFrame { df with arrow_table = Arrow_table.create updated_cols nrows }
            | VDict row_items ->
                (* scalar broadcast: apply the same Dict to every matched row *)
                let updated_cols = List.map (fun name ->
                  let col = match Arrow_table.get_column df.arrow_table name with
                    | Some c -> c | None -> Arrow_table.NullColumn nrows
                  in
                  let vals = Arrow_bridge.column_to_values col in
                  let new_val = match List.assoc_opt name row_items with
                    | Some v -> v | None -> VNA NAGeneric
                  in
                  for i = 0 to nrows - 1 do
                    if mask.(i) then vals.(i) <- new_val
                  done;
                  (name, Arrow_bridge.values_to_column vals)
                ) names in
                VDataFrame { df with arrow_table = Arrow_table.create updated_cols nrows }
            | other ->
                Error.type_error
                  (Printf.sprintf
                     "filter_lens set on DataFrame expects a Dict or DataFrame, got %s"
                     (Utils.type_name other))))
  | [(_, other); _] ->
      Error.type_error (Printf.sprintf "filter_lens set expects a Collection, got %s"
        (Utils.type_name other))
  | _ -> Error.arity_error_named "filter_lens.set" 2 (List.length args)

(*
--# Filter Lens
--#
--# Targets elements in a List/Vector or rows in a DataFrame that satisfy a predicate.
--#
--# @name filter_lens
--# @param p :: Function The predicate function.
--# @return :: Lens A lens for elements matching the predicate.
--# @family lens
--# @export
*)
let filter_lens_impl ~eval_call args _env =
  match args with
  | [(_, VNA _)] -> Error.type_error "filter_lens: predicate cannot be NA"
  | [(_, p)] ->
      let get_fn = VBuiltin {
        b_name = None; b_arity = 1; b_variadic = false;
        b_func = (fun args env_ref -> filter_lens_get_impl p ~eval_call args !env_ref)
      } in
      let set_fn = VBuiltin {
        b_name = None; b_arity = 2; b_variadic = false;
        b_func = (fun args env_ref -> filter_lens_set_impl p ~eval_call args !env_ref)
      } in
      VDict [("get", get_fn); ("set", set_fn)]
  | _ -> Error.arity_error_named "filter_lens" 1 (List.length args)

(*
--# Transform Focused Value
--#
--# Applies a function to the value focused by a lens and returns the updated structure.
--#
--# @name over
--# @param data :: Any The input structure.
--# @param lens :: Lens The lens defining the focus.
--# @param func :: Function The transformation function.
--# @return :: Any The updated structure.
--# @family lens
--# @export
*)
let over_impl ~eval_call args env =
  match args with
  | [(_, data); (_, lens); (_, func)] ->
      over_val ~eval_call (ref env) lens data func
  | _ -> Error.arity_error_named "over" 3 (List.length args)

(*
--# Get Value via Lens
--#
--# Retrieves a focused value from a data structure using a lens.
--#
--# @name get
--# @param data :: Any The data structure to focus on.
--# @param lens :: Lens The lens defining the focus.
--# @return :: Any The focused value.
--# @family lens
--# @export
*)
let get_impl ~eval_call args env =
  match args with
  | [(_, data); (_, VDict items)] ->
      (match List.assoc_opt "get" items with
       | Some get_fn -> eval_call env get_fn [(None, mk_expr (Value data))]
       | None -> Error.type_error "Lens missing get function")
  | [(_, VList items); (_, VInt i)] ->
      let len = List.length items in
      if i < 0 || i >= len then Error.index_error i len
      else let (_, v) = List.nth items i in v
  | [(_, VVector arr); (_, VInt i)] ->
      let len = Array.length arr in
      if i < 0 || i >= len then Error.index_error i len
      else arr.(i)
  | [(_, VNDArray arr); (_, VInt i)] ->
      let len = Array.length arr.data in
      if i < 0 || i >= len then Error.index_error i len
      else VFloat arr.data.(i)
  | [(_, _); (_, other)] ->
      Error.type_error (Printf.sprintf "get expects either (data, Lens) or (collection, Index). Got %s for the second argument." (Utils.type_name other))
  | _ -> Error.arity_error_named "get" 2 (List.length args)

(*
--# Compose Lenses
--#
--# Combines two lenses into one, focusing on a value deep within a nested structure.
--#
--# @name compose
--# @param lens1 :: Lens The outer lens.
--# @param lens2 :: Lens The inner lens.
--# @return :: Lens The composite lens.
--# @family lens
--# @export
*)
let compose2 ~eval_call lens1 lens2 =
  match lens1, lens2 with
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
  | (VError _ as e), _ -> e
  | _, (VError _ as e) -> e
  | _ -> Error.type_error "compose expects Lenses"

let compose_impl ~eval_call args _env =
  match args with
  | [] -> Error.arity_error_named "compose" 2 0
  | [(_, l)] -> l
  | (_, l1) :: rest ->
      List.fold_left (fun acc (_, l_next) -> 
        match acc with
        | VError _ -> acc
        | _ -> compose2 ~eval_call acc l_next
      ) l1 rest

(*
--# Set Focused Value
--#
--# Replaces the value focused by a lens with a new value.
--#
--# @name set
--# @param data :: Any The input structure.
--# @param lens :: Lens The lens defining the focus.
--# @param value :: Any The new value to set.
--# @return :: Any The updated structure.
--# @family lens
--# @export
*)
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

(*
--# Multiple Lens Transformations
--#
--# Applies a sequence of lens-based transformations to the same data structure.
--# Takes pairs of (lens, function).
--#
--# @name modify
--# @param data :: Any The input structure.
--# @param ... :: Lens, Function Sequence of lens and transformation function pairs.
--# @return :: Any The final updated structure.
--# @family lens
--# @export
*)
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

(*
--# Pipeline Node Lens
--#
--# Targets the cached result value of a specific node in a Pipeline.
--#
--# @name node_lens
--# @param node_name :: String The name of the node.
--# @return :: Lens A lens for the node's value.
--# @family lens
--# @export
*)
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

(*
--# Pipeline Env Var Lens
--#
--# Targets a specific environment variable for a node in a Pipeline.
--#
--# @name env_var_lens
--# @param node_name :: String The name of the node.
--# @param var_name :: String The name of the environment variable.
--# @return :: Lens A lens for the environment variable.
--# @family lens
--# @export
*)
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
  let make_l_builtin ?(variadic=false) name arity f env =
    Env.add name (VBuiltin { b_name = Some name; b_arity = arity; b_variadic = variadic; b_func = (fun args env_ref -> f ~eval_call args !env_ref) }) env
  in
  env
  |> make_l_builtin "col_lens" 1 col_lens_impl
  |> make_l_builtin "over" 3 over_impl
  |> make_l_builtin "get" 2 get_impl
  |> make_l_builtin ~variadic:true "compose" 2 compose_impl
  |> make_l_builtin "set" 3 set_impl
  |> make_l_builtin ~variadic:true "modify" 1 modify_impl
  |> make_l_builtin "node_lens" 1 node_lens_impl
  |> make_l_builtin "env_var_lens" 2 env_var_lens_impl
  |> make_l_builtin "idx_lens" 1 idx_lens_impl
  |> make_l_builtin "row_lens" 1 row_lens_impl
  |> make_l_builtin "filter_lens" 1 filter_lens_impl
