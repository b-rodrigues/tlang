open Ast
open Arrow_table

(* expand_input describes one "slot" of the cartesian product:
   - Single: all unique values of a single column
   - Nested: all existing row-wise combinations of a group of columns *)
type expand_input =
  | Single of string * value list
  | Nested of string list * (value list) list

(*
--# Complete a data frame
--#
--# Turns implicit missing values into explicit missing values.
--# Supports nesting() to restrict combinations to those present in the data.
--#
--# @name complete
--# @param df :: DataFrame The DataFrame.
--# @param ... :: Symbol | Call Variable number of column names (use $col syntax) or nesting(...) calls.
--# @param fill :: Dict (Optional) A dictionary supplying a single value to use instead of NA for missing combinations.
--# @param explicit :: Bool (Optional) Should both implicit and explicit missing values be filled? (Default: true)
--# @return :: DataFrame The completed DataFrame.
--# @example
--#   complete(df, $group, $item_id, $item_name)
--#   complete(df, $group, nesting($item_id, $item_name))
--# @family colcraft
--# @export
*)
let register env =
  Env.add "complete"
    (make_builtin_named ~name:"complete" ~variadic:true 1 (fun named_args _env ->
      let df_arg = match named_args with
        | (_, VDataFrame df) :: _ -> Some df
        | _ -> None
      in
      
      let get_named k = List.find_map (fun (nk, v) -> if nk = Some k then Some v else None) named_args in
      let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) named_args in
      
      let fill_dict = match get_named "fill" with
        | Some (VDict d) -> d
        | _ -> []
      in

      let explicit_val = match get_named "explicit" with
        | Some (VBool b) -> b
        | _ -> true
      in
      
      let id_cols_variants = match positional with _::tail -> tail | [] -> [] in

      match df_arg with
      | None -> Error.type_error "Function `complete` expects a DataFrame as first argument."
      | Some df ->
          
          let orig_nrows = Arrow_table.num_rows df.arrow_table in
          let all_cols = Arrow_table.column_names df.arrow_table in

          (* Gather a single value from a column at a given row index *)
          let get_val col i =
            match Arrow_table.get_column df.arrow_table col with
             | Some (StringColumn a) -> (match a.(i) with Some x -> VString x | None -> VNA NAGeneric)
             | Some (IntColumn a) -> (match a.(i) with Some x -> VInt x | None -> VNA NAGeneric)
             | Some (FloatColumn a) -> (match a.(i) with Some x -> VFloat x | None -> VNA NAGeneric)
             | Some (BoolColumn a) -> (match a.(i) with Some x -> VBool x | None -> VNA NAGeneric)
             | _ -> VNA NAGeneric
          in

          (* Get unique values for a single column (insertion-order preserved) *)
          let get_unique_vals col =
            let seen = Hashtbl.create orig_nrows in
            let ordered = ref [] in
            for i = 0 to orig_nrows - 1 do
              let v = get_val col i in
              if not (Hashtbl.mem seen v) then begin
                Hashtbl.add seen v ();
                ordered := v :: !ordered
              end
            done;
            List.rev !ordered
          in

          (* Get unique row-wise combinations for a set of columns (sorted) *)
          let get_nested_combos cols =
            let seen = Hashtbl.create orig_nrows in
            let ordered = ref [] in
            for i = 0 to orig_nrows - 1 do
              let row = List.map (fun c -> get_val c i) cols in
              if not (Hashtbl.mem seen row) then begin
                Hashtbl.add seen row ();
                ordered := row :: !ordered
              end
            done;
            List.rev !ordered
          in

          (* Parse each positional arg into an expand_input.
             nesting() returns a VDict with key "__nesting__" (see expand.ml:nesting_impl);
             we detect this marker here to restrict those columns to existing combinations. *)
          let expand_inputs = List.filter_map (fun v ->
            match v with
            | VDict d when List.mem_assoc "__nesting__" d ->
                (* Dict produced by nesting(): cols holds the column symbol list *)
                let cols = match List.assoc_opt "cols" d with
                  | Some (VList l) -> List.filter_map (fun (_, sv) -> Utils.extract_column_name sv) l
                  | _ -> []
                in
                if cols = [] then None
                else Some (Nested (cols, get_nested_combos cols))
            | _ ->
                (match Utils.extract_column_name v with
                 | Some col -> Some (Single (col, get_unique_vals col))
                 | None -> None)
          ) id_cols_variants in

          if expand_inputs = [] then
            Error.make_error ValueError "Function `complete` requires at least one column or nesting() expression."
          else

          (* Flat list of all id column names, in order *)
          let id_cols = List.concat_map (function
            | Single (n, _) -> [n]
            | Nested (ns, _) -> ns
          ) expand_inputs in

          let missing_cols = List.filter (fun c -> not (List.mem c all_cols)) id_cols in
          if missing_cols <> [] then Error.make_error KeyError (Printf.sprintf "Column(s) not found: %s" (String.concat ", " missing_cols)) else

          (* Cartesian product of unique values *)
          let rec cartesian lists =
            match lists with
            | [] -> [[]]
            | h :: t ->
                let t_prod = cartesian t in
                List.concat (List.map (fun elm -> List.map (fun t_line -> elm :: t_line) t_prod) h)
          in
          (* Each expand_input contributes one "slot": Single -> list of single-element lists;
             Nested -> list of multi-element lists (the existing combinations). *)
          let combo_lists = List.map (function
            | Single (_, vals) -> List.map (fun v -> [v]) vals
            | Nested (_, combos) -> combos
          ) expand_inputs in
          let combos = cartesian combo_lists |> List.map List.flatten in
          
          let combo_to_rows = Hashtbl.create orig_nrows in
          for i = 0 to orig_nrows - 1 do
             let current_combo = List.map (fun c -> get_val c i) id_cols in
             let current_list = match Hashtbl.find_opt combo_to_rows current_combo with Some l -> l | None -> [] in
             Hashtbl.replace combo_to_rows current_combo (i :: current_list)
          done;

          (* Build the output rows *)
          let out_row_indices = ref [] in
          let combo_for_out_row = ref [] in

          List.iter (fun combo ->
             match Hashtbl.find_opt combo_to_rows combo with
             | Some row_indices -> 
                 List.iter (fun r -> 
                   out_row_indices := (Some r) :: !out_row_indices; 
                   combo_for_out_row := combo :: !combo_for_out_row
                 ) (List.rev row_indices)
             | None -> 
                 out_row_indices := None :: !out_row_indices;
                 combo_for_out_row := combo :: !combo_for_out_row
          ) combos;

          let final_out_row_indices = List.rev !out_row_indices in
          let final_combos = List.rev !combo_for_out_row in
          let final_nrows = List.length final_out_row_indices in
          (* Convert to arrays for O(1) indexed access during column reconstruction *)
          let final_out_row_indices_arr = Array.of_list final_out_row_indices in
          let final_combos_arr = Array.of_list final_combos in

          (* Reconstruct columns *)
          let new_columns = List.map (fun col_name ->
            let is_id_col = List.mem col_name id_cols in
            let id_idx = if is_id_col then
               let rec find_idx lst curr = match lst with h::t -> if h = col_name then curr else find_idx t (curr + 1) | [] -> -1 in
               find_idx id_cols 0
             else -1
            in

            let col_data = match Arrow_table.get_column df.arrow_table col_name with
              | Some d -> d
              | None -> NullColumn orig_nrows
            in

            let new_col_data = 
               if is_id_col then
                  let extract_combo_val i = List.nth final_combos_arr.(i) id_idx in
                  match col_data with
                  | IntColumn _ -> IntColumn (Array.init final_nrows (fun i -> match extract_combo_val i with VInt x -> Some x | _ -> None))
                  | FloatColumn _ -> FloatColumn (Array.init final_nrows (fun i -> match extract_combo_val i with VFloat x -> Some x | _ -> None))
                  | StringColumn _ -> StringColumn (Array.init final_nrows (fun i -> match extract_combo_val i with VString x -> Some x | _ -> None))
                  | BoolColumn _ -> BoolColumn (Array.init final_nrows (fun i -> match extract_combo_val i with VBool x -> Some x | _ -> None))
                  | NullColumn _ -> NullColumn final_nrows
                  | DictionaryColumn (_, levels, ordered) -> DictionaryColumn (Array.init final_nrows (fun i -> match extract_combo_val i with VFactor (x, _, _) -> Some x | _ -> None), levels, ordered)
               else
                  let fill_val = List.assoc_opt col_name fill_dict in
                  match col_data with
                  | IntColumn a -> 
                      let fill_i = match fill_val with Some (VInt i) -> Some i | Some (VFloat f) -> Some (int_of_float f) | _ -> None in
                      IntColumn (Array.init final_nrows (fun i -> 
                        match final_out_row_indices_arr.(i) with 
                        | Some r -> (match a.(r) with Some x -> Some x | None -> if explicit_val then fill_i else None)
                        | None -> fill_i))
                  | FloatColumn a -> 
                      let fill_f = match fill_val with Some (VFloat f) -> Some f | Some (VInt i) -> Some (float_of_int i) | _ -> None in
                      FloatColumn (Array.init final_nrows (fun i -> 
                        match final_out_row_indices_arr.(i) with 
                        | Some r -> (match a.(r) with Some x -> Some x | None -> if explicit_val then fill_f else None)
                        | None -> fill_f))
                  | StringColumn a -> 
                      let fill_s = match fill_val with Some (VString s) -> Some s | _ -> None in
                      StringColumn (Array.init final_nrows (fun i -> 
                        match final_out_row_indices_arr.(i) with 
                        | Some r -> (match a.(r) with Some x -> Some x | None -> if explicit_val then fill_s else None)
                        | None -> fill_s))
                  | BoolColumn a -> 
                      let fill_b = match fill_val with Some (VBool b) -> Some b | _ -> None in
                      BoolColumn (Array.init final_nrows (fun i -> 
                        match final_out_row_indices_arr.(i) with 
                        | Some r -> (match a.(r) with Some x -> Some x | None -> if explicit_val then fill_b else None)
                        | None -> fill_b))
                  | NullColumn _ -> NullColumn final_nrows
                  | DictionaryColumn (a, levels, ordered) ->
                      let fill_i = match fill_val with Some (VFactor (i, _, _)) -> Some i | _ -> None in
                      DictionaryColumn (Array.init final_nrows (fun i -> 
                        match final_out_row_indices_arr.(i) with 
                        | Some r -> (match a.(r) with Some x -> Some x | None -> if explicit_val then fill_i else None)
                        | None -> fill_i), levels, ordered)
            in
            (col_name, new_col_data)

          ) all_cols in

          let new_schema = List.map (fun (n, c) -> (n, Arrow_table.column_type_of c)) new_columns in
          VDataFrame { arrow_table = { schema = new_schema; columns = new_columns; nrows = final_nrows; native_handle = None } |> Arrow_table.materialize; group_keys = df.group_keys }
    ))
    env
