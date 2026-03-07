(* src/packages/colcraft/factors.ml *)
open Ast

(* Convert values to optional strings: NA values become None (and are preserved
   as VNA in the output factor), non-string values are stringified.
   None entries are excluded from level derivation. *)
let as_string_list_opt values =
  let rec aux acc = function
    | [] -> List.rev acc
    | VNA _ :: t -> aux (None :: acc) t
    | VString s :: t -> aux (Some s :: acc) t
    | v :: t -> aux (Some (Utils.value_to_string v) :: acc) t
  in aux [] values

(* Scan an array for the first VFactor element and return its (levels, ordered).
   Skips VNA and any other non-Factor values, so NA-leading vectors are handled
   correctly. Returns None if no VFactor is found. *)
let find_first_factor_in_array arr =
  let n = Array.length arr in
  let rec aux i =
    if i >= n then None
    else match arr.(i) with
      | VFactor (_, levels, ordered) -> Some (levels, ordered)
      | _ -> aux (i + 1)
  in aux 0

(* Return the index of string [s] in the level list [levels], or None if absent.
   Used by replace_na and complete when accepting a VString fill value for a
   DictionaryColumn. *)
let level_index_of levels s =
  let rec aux i = function
    | [] -> None
    | h :: _ when h = s -> Some i
    | _ :: t -> aux (i + 1) t
  in aux 0 levels

let factor_generic ~fct_mode (args : (string option * value) list) _env =
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
  let named = List.filter_map (fun (k, v) -> match k with Some n -> Some (n, v) | None -> None) args in
  match positional with
  | [] -> Error.make_error Ast.ArityError "factor expects at least 1 argument"
  | x_val :: _ ->
      let items = match x_val with
        | VVector a -> Array.to_list a
        | VList l -> List.map snd l
        | _ -> [x_val]
      in
      let string_opts = as_string_list_opt items in

      (* Only non-NA values contribute to level derivation *)
      let non_na_strings = List.filter_map Fun.id string_opts in
      let unique_levels = 
        if fct_mode then
          (* for fct(), levels follow first appearance *)
          let rec first_appearance acc = function
            | [] -> List.rev acc
            | h :: t -> if List.mem h acc then first_appearance acc t else first_appearance (h :: acc) t
          in first_appearance [] non_na_strings
        else
          List.sort_uniq String.compare non_na_strings
      in

      let levels =
        match List.assoc_opt "levels" named with
        | Some (VVector a) -> List.filter_map Fun.id (as_string_list_opt (Array.to_list a))
        | Some (VList l) -> List.filter_map Fun.id (as_string_list_opt (List.map snd l))
        | _ -> unique_levels
      in

      let ordered =
        match List.assoc_opt "ordered" named with
        | Some (VBool b) -> b
        | _ -> false
      in

      (* Pre-compute level -> index table for O(1) lookup per element *)
      let level_tbl = Hashtbl.create (List.length levels) in
      List.iteri (fun i l -> Hashtbl.add level_tbl l i) levels;

      let factor_arr = Array.of_list string_opts |> Array.map (function
        | None -> VNA Ast.NAGeneric
        | Some s ->
            (match Hashtbl.find_opt level_tbl s with
             | Some idx -> VFactor (idx, levels, ordered)
             | None -> VNA Ast.NAGeneric (* NA if value is not in levels *))
      ) in
      VVector factor_arr

let factor_impl = factor_generic ~fct_mode:false
let fct_impl = factor_generic ~fct_mode:true
let ordered_impl (args : (string option * value) list) _env =
  (* same as factor but defaults ordered=true *)
  let named = List.filter_map (fun (k, v) -> match k with Some n -> Some (n, v) | None -> None) args in
  let has_ordered = List.mem_assoc "ordered" named in
  if has_ordered then factor_impl args _env
  else factor_impl ((Some "ordered", VBool true) :: args) _env

let as_factor_impl args env =
  factor_impl args env

let fct_infreq_impl args _env =
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
  match positional with
  | [VVector arr] ->
      let factors = Array.to_list arr in
      let c, levels, ordered =
        match find_first_factor_in_array arr with
        | Some (l, o) -> true, l, o
        | None -> false, [], false
      in
      if not c then VVector arr
      else
        let counts = Hashtbl.create (List.length levels) in
        List.iter (fun v -> match v with
          | VFactor(i, _, _) ->
              let prev = match Hashtbl.find_opt counts i with Some c -> c | None -> 0 in
              Hashtbl.replace counts i (prev + 1)
          | _ -> ()
        ) factors;

        let new_levels = levels
          |> List.mapi (fun i l -> (i, l, match Hashtbl.find_opt counts i with Some c -> c | None -> 0))
          |> List.sort (fun (_, _, c1) (_, _, c2) -> compare c2 c1)
          |> List.map (fun (_, l, _) -> l)
        in

        (* Pre-compute new level -> index table for O(1) remapping *)
        let new_level_tbl = Hashtbl.create (List.length new_levels) in
        List.iteri (fun i l -> Hashtbl.add new_level_tbl l i) new_levels;

        let factor_arr = Array.map (fun v -> match v with
          | VFactor (i, _, _) ->
              (match List.nth_opt levels i with
               | Some s ->
                   let new_idx = match Hashtbl.find_opt new_level_tbl s with
                     | Some idx -> idx
                     | None -> 0
                   in
                   VFactor (new_idx, new_levels, ordered)
               | None ->
                   (* Out-of-range factor index; treat as NA to avoid crashing *)
                   VNA Ast.NAGeneric)
          | _ -> v
        ) arr in
        VVector factor_arr
  | _ -> Error.make_error Ast.ArityError "fct_infreq expects 1 argument (vector of factors)"

let levels_impl args _env =
  match args with
  | [VVector arr] ->
      if Array.length arr = 0 then VVector [||]
      else
        (match find_first_factor_in_array arr with
         | Some (levels, _) -> VVector (Array.of_list (List.map (fun s -> VString s) levels))
         | None -> VVector [||])
  | _ -> Error.make_error Ast.ArityError "levels expects 1 argument"

let fct_rev_impl args _env =
  match args with
  | [VVector arr] ->
      if Array.length arr = 0 then VVector [||]
      else
        (match find_first_factor_in_array arr with
         | Some (levels, ordered) ->
             let new_levels = List.rev levels in
             let n = List.length levels in
             let factor_arr = Array.map (function
               | VFactor (i, _, _) -> VFactor (n - 1 - i, new_levels, ordered)
               | v -> v
             ) arr in
             VVector factor_arr
         | None -> VVector arr)
  | _ -> Error.make_error Ast.ArityError "fct_rev expects 1 argument"

let fct_recode_impl (args : (string option * value) list) _env =
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
  let named = List.filter_map (fun (k, v) -> match k with Some n -> Some (n, v) | None -> None) args in
  match positional with
  | [VVector arr] ->
      if Array.length arr = 0 then VVector [||]
      else
        (match find_first_factor_in_array arr with
         | Some (levels, ordered) ->
            (* named: new_level = old_level *)
            let recode_map = List.filter_map (fun (new_l, old_v) ->
              match old_v with
              | VString old_l -> Some (old_l, new_l)
              | _ -> None
            ) named in
            
            let new_levels_with_dups = List.map (fun l ->
              match List.assoc_opt l recode_map with
              | Some new_l -> new_l
              | None -> l
            ) levels in
            
            (* Deduplicate levels if multiple old levels mapped to same new level *)
            let final_levels = 
              let rec unique acc = function
                | [] -> List.rev acc
                | h :: t -> if List.mem h acc then unique acc t else unique (h :: acc) t
              in unique [] new_levels_with_dups
            in
            
            let level_remapping = List.mapi (fun _i old_l ->
              let new_l = match List.assoc_opt old_l recode_map with Some nl -> nl | None -> old_l in
              match List.find_index (fun l -> l = new_l) final_levels with
              | Some idx -> idx
              | None -> 0
            ) levels |> Array.of_list in
            
            let factor_arr = Array.map (function
              | VFactor (i, _, _) ->
                  let new_idx = level_remapping.(i) in
                  VFactor (new_idx, final_levels, ordered)
              | v -> v
            ) arr in
            VVector factor_arr
         | None -> VVector arr)
  | _ -> Error.make_error Ast.ArityError "fct_recode expects at least 1 argument"

let fct_reorder_impl (args : (string option * value) list) _env =
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
  let named = List.filter_map (fun (k, v) -> match k with Some n -> Some (n, v) | None -> None) args in
  match positional with
  | [VVector f_arr; VVector x_arr] ->
      if Array.length f_arr = 0 then VVector [||]
      else
        (match find_first_factor_in_array f_arr with
         | Some (levels, ordered) ->
             let n = Array.length f_arr in
             let desc = match List.assoc_opt ".desc" named with Some (VBool b) -> b | _ -> false in
             
             (* Group .x values by factor levels *)
             let level_data = Array.init (List.length levels) (fun _ -> []) in
             for i = 0 to n - 1 do
               match f_arr.(i) with
               | VFactor (idx, _, _) -> 
                   (match x_arr.(i) with
                    | VInt x -> level_data.(idx) <- float_of_int x :: level_data.(idx)
                    | VFloat x -> level_data.(idx) <- x :: level_data.(idx)
                    | _ -> ())
               | _ -> ()
             done;
             
             (* Calculate summary (median by default) *)
             let summaries = Array.mapi (fun i data ->
               if data = [] then (i, neg_infinity)
               else
                 let sorted = List.sort Float.compare data in
                 let len = List.length sorted in
                 let median = 
                   if len mod 2 = 1 then List.nth sorted (len / 2)
                   else (List.nth sorted (len / 2 - 1) +. List.nth sorted (len / 2)) /. 2.
                 in
                 (i, median)
             ) level_data in
             
             let sorted_summaries = Array.to_list summaries |> List.sort (fun (_, s1) (_, s2) ->
               if desc then Float.compare s2 s1 else Float.compare s1 s2
             ) in
             
             let new_level_order = List.map fst sorted_summaries in
             let new_levels = List.map (fun i -> List.nth levels i) new_level_order in
             let remapping = Array.make (List.length levels) 0 in
             List.iteri (fun i old_idx -> remapping.(old_idx) <- i) new_level_order;
             
             let factor_arr = Array.map (function
               | VFactor (i, _, _) -> VFactor (remapping.(i), new_levels, ordered)
               | v -> v
             ) f_arr in
             VVector factor_arr
         | None -> VVector f_arr)
  | _ -> Error.make_error Ast.ArityError "fct_reorder expects at least 2 arguments (.f and .x)"

let fct_lump_n_impl (args : (string option * value) list) _env =
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
  let named = List.filter_map (fun (k, v) -> match k with Some n -> Some (n, v) | None -> None) args in
  match positional with
  | [VVector arr] ->
      if Array.length arr = 0 then VVector [||]
      else
        (match find_first_factor_in_array arr with
         | Some (levels, ordered) ->
             let n_limit = match List.assoc_opt "n" named with Some (VInt n) -> n | _ -> 10 in
             let other_level = match List.assoc_opt "other_level" named with Some (VString s) -> s | _ -> "Other" in
             
             let counts = Hashtbl.create (List.length levels) in
             Array.iter (function
               | VFactor (i, _, _) -> 
                   let prev = match Hashtbl.find_opt counts i with Some c -> c | None -> 0 in
                   Hashtbl.replace counts i (prev + 1)
               | _ -> ()
             ) arr;
             
             let sorted_counts = List.mapi (fun i l -> (i, l, match Hashtbl.find_opt counts i with Some c -> c | None -> 0)) levels
                                |> List.sort (fun (_, _, c1) (_, _, c2) -> compare c2 c1) in
             
             let top_n = List.filteri (fun i _ -> i < n_limit) sorted_counts in
             let top_indices = List.map (fun (i, _, _) -> i) top_n in
             
             let new_levels = (List.map (fun (_, l, _) -> l) top_n) @ [other_level] in
             let other_idx = List.length new_levels - 1 in
             
             let remapping = Array.make (List.length levels) other_idx in
             List.iteri (fun i old_idx -> remapping.(old_idx) <- i) top_indices;
             
             let factor_arr = Array.map (function
               | VFactor (i, _, _) -> VFactor (remapping.(i), new_levels, ordered)
               | v -> v
             ) arr in
             VVector factor_arr
         | None -> VVector arr)
  | _ -> Error.make_error Ast.ArityError "fct_lump_n expects 1 argument"

let fct_relevel_impl (args : (string option * value) list) _env =
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
  let named = List.filter_map (fun (k, v) -> match k with Some n -> Some (n, v) | None -> None) args in
  match positional with
  | VVector f_arr :: levels_to_move ->
      if Array.length f_arr = 0 then VVector [||]
      else
        (match find_first_factor_in_array f_arr with
         | Some (levels, ordered) ->
             let to_move = List.filter_map (function VString s -> Some s | _ -> None) levels_to_move in
             let after = match List.assoc_opt "after" named with Some (VInt i) -> i | _ -> 0 in
             
             let stable_other = List.filter (fun l -> not (List.mem l to_move)) levels in
             let new_levels = 
               if after = 0 then to_move @ stable_other
               else if after >= List.length stable_other then stable_other @ to_move
               else 
                 let rec insert i acc = function
                   | [] -> List.rev acc
                   | h :: t -> if i = after then List.rev (to_move @ (h :: acc)) @ t else insert (i + 1) (h :: acc) t
                 in insert 1 [] stable_other
             in
             
             let remapping = Array.make (List.length levels) 0 in
             List.iteri (fun i old_l ->
               match List.find_index (fun l -> l = old_l) new_levels with
               | Some idx -> remapping.(i) <- idx
               | None -> ()
             ) levels;
             
             let factor_arr = Array.map (function
               | VFactor (i, _, _) -> VFactor (remapping.(i), new_levels, ordered)
               | v -> v
             ) f_arr in
             VVector factor_arr
         | None -> VVector f_arr)
  | _ -> Error.make_error Ast.ArityError "fct_relevel expects at least 1 argument"

let fct_collapse_impl (args : (string option * value) list) _env =
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
  let named = List.filter_map (fun (k, v) -> match k with Some n -> Some (n, v) | None -> None) args in
  match positional with
  | [VVector arr] ->
      if Array.length arr = 0 then VVector [||]
      else
        (match find_first_factor_in_array arr with
         | Some (levels, ordered) ->
             (* named: new_level = [old_level1, old_level2] *)
             let collapse_map = List.filter_map (fun (new_l, old_vs) ->
               match old_vs with
               | VVector a -> Some (Array.to_list a |> List.filter_map (function VString s -> Some s | _ -> None), new_l)
               | VList l -> Some (List.map snd l |> List.filter_map (function VString s -> Some s | _ -> None), new_l)
               | VString s -> Some ([s], new_l)
               | _ -> None
             ) named in
             
             let new_levels_with_dups = List.map (fun l ->
               match List.find (fun (olds, _) -> List.mem l olds) collapse_map with
               | exception Not_found -> l
               | (_, new_l) -> new_l
             ) levels in
             
             let final_levels = 
                let rec unique acc = function
                  | [] -> List.rev acc
                  | h :: t -> if List.mem h acc then unique acc t else unique (h :: acc) t
                in unique [] new_levels_with_dups
             in
             
             let level_remapping = List.mapi (fun _i old_l ->
               let new_l = match List.find (fun (olds, _) -> List.mem old_l olds) collapse_map with
                 | exception Not_found -> old_l
                 | (_, nl) -> nl
               in
               match List.find_index (fun l -> l = new_l) final_levels with
               | Some idx -> idx
               | None -> 0
             ) levels |> Array.of_list in
             
             let factor_arr = Array.map (function
               | VFactor (i, _, _) -> VFactor (level_remapping.(i), final_levels, ordered)
               | v -> v
             ) arr in
             VVector factor_arr
         | None -> VVector arr)
  | _ -> Error.make_error Ast.ArityError "fct_collapse expects at least 1 argument"

let count_levels levels arr =
  let counts = Array.make (List.length levels) 0 in
  Array.iter (function
    | VFactor (i, _, _) when i >= 0 && i < Array.length counts ->
        counts.(i) <- counts.(i) + 1
    | _ -> ()
  ) arr;
  counts

let remap_factor_array arr levels ordered new_levels remapping =
  let factor_arr = Array.map (function
    | VFactor (i, _, _) when i >= 0 && i < Array.length remapping ->
        let new_idx = remapping.(i) in
        if new_idx < 0 then VNA Ast.NAGeneric else VFactor (new_idx, new_levels, ordered)
    | VFactor _ -> VNA Ast.NAGeneric
    | value -> value
  ) arr in
  VVector factor_arr

let append_unique_levels base candidates =
  let seen = Hashtbl.create (List.length base + List.length candidates) in
  List.iter (fun level -> Hashtbl.replace seen level ()) base;
  let extras_rev = ref [] in
  List.iter (fun level ->
    if not (Hashtbl.mem seen level) then begin
      Hashtbl.replace seen level ();
      extras_rev := level :: !extras_rev
    end
  ) candidates;
  base @ List.rev !extras_rev

let string_values_of function_name value =
  match value with
  | VString s -> Ok [s]
  | VVector arr ->
      Array.fold_right (fun item acc ->
        match item, acc with
        | VString s, Ok values -> Ok (s :: values)
        | _, Ok _ ->
            Error
              (Error.type_error
                 (Printf.sprintf "Function `%s` expects string level names." function_name))
        | _, Error err -> Error err
      ) arr (Ok [])
  | VList items ->
      List.fold_right (fun (_, item) acc ->
        match item, acc with
        | VString s, Ok values -> Ok (s :: values)
        | _, Ok _ ->
            Error
              (Error.type_error
                 (Printf.sprintf "Function `%s` expects string level names." function_name))
        | _, Error err -> Error err
      ) items (Ok [])
  | _ ->
      Error
        (Error.type_error
           (Printf.sprintf "Function `%s` expects string level names." function_name))

let fct_lump_min_impl (args : (string option * value) list) _env =
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
  let named = List.filter_map (fun (k, v) -> match k with Some n -> Some (n, v) | None -> None) args in
  match positional with
  | [VVector arr; VInt min_count] ->
      if Array.length arr = 0 then VVector [||]
      else
        (match find_first_factor_in_array arr with
         | Some (levels, ordered) ->
             let other_level =
               match List.assoc_opt "other_level" named with
               | Some (VString s) -> s
               | _ -> "Other"
             in
             let counts = count_levels levels arr in
             let kept_levels =
               List.mapi (fun idx level -> (idx, level)) levels
               |> List.filter (fun (idx, _) -> counts.(idx) >= min_count)
             in
              if List.length kept_levels = List.length levels then
                VVector arr
              else
                let new_levels = List.rev (other_level :: List.rev (List.map snd kept_levels)) in
                let other_idx = List.length new_levels - 1 in
                let remapping = Array.make (List.length levels) other_idx in
                List.iteri (fun new_idx (old_idx, _) -> remapping.(old_idx) <- new_idx) kept_levels;
                remap_factor_array arr levels ordered new_levels remapping
         | None -> VVector arr)
  | _ -> Error.make_error Ast.ArityError "fct_lump_min expects a factor vector and minimum count"

let fct_lump_prop_impl (args : (string option * value) list) _env =
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
  let named = List.filter_map (fun (k, v) -> match k with Some n -> Some (n, v) | None -> None) args in
  let prop_of_value = function
    | VFloat f -> Some f
    | VInt i -> Some (float_of_int i)
    | _ -> None
  in
  match positional with
  | [VVector arr; prop_value] ->
      (match prop_of_value prop_value with
       | None ->
           Error.type_error "Function `fct_lump_prop` expects a numeric proportion."
       | Some prop ->
           if prop < 0.0 || prop > 1.0 then
             Error.value_error "Function `fct_lump_prop` proportion must be between 0 and 1."
           else if Array.length arr = 0 then
             VVector [||]
           else
             (match find_first_factor_in_array arr with
              | Some (levels, ordered) ->
                  let other_level =
                    match List.assoc_opt "other_level" named with
                    | Some (VString s) -> s
                    | _ -> "Other"
                  in
                  let counts = count_levels levels arr in
                  let total =
                    Array.fold_left ( + ) 0 counts |> float_of_int
                  in
                  let kept_levels =
                    List.mapi (fun idx level -> (idx, level)) levels
                    |> List.filter (fun (idx, _) ->
                         total > 0.0 && (float_of_int counts.(idx) /. total) >= prop)
                  in
                   if List.length kept_levels = List.length levels then
                     VVector arr
                   else
                    let new_levels = List.rev (other_level :: List.rev (List.map snd kept_levels)) in
                    let other_idx = List.length new_levels - 1 in
                    let remapping = Array.make (List.length levels) other_idx in
                    List.iteri (fun new_idx (old_idx, _) -> remapping.(old_idx) <- new_idx) kept_levels;
                    remap_factor_array arr levels ordered new_levels remapping
              | None -> VVector arr))
  | _ -> Error.make_error Ast.ArityError "fct_lump_prop expects a factor vector and proportion"

let fct_other_impl (args : (string option * value) list) _env =
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
  let named = List.filter_map (fun (k, v) -> match k with Some n -> Some (n, v) | None -> None) args in
  let extract_names field =
    match List.assoc_opt field named with
    | Some value ->
        string_values_of "fct_other" value
    | None -> Ok []
  in
  match positional with
  | [VVector arr] ->
      (match find_first_factor_in_array arr, extract_names "keep", extract_names "drop" with
       | Some (levels, ordered), Ok keep, Ok drop ->
           if keep <> [] && drop <> [] then
             Error.value_error "Function `fct_other` accepts either `keep` or `drop`, not both."
           else
             let other_level =
               match List.assoc_opt "other_level" named with
               | Some (VString s) -> s
               | _ -> "Other"
             in
             let keep_levels =
               if keep <> [] then keep else List.filter (fun level -> not (List.mem level drop)) levels
             in
             let kept_present = List.filter (fun level -> List.mem level keep_levels) levels in
             let new_levels =
               if List.length kept_present = List.length levels then kept_present
               else kept_present @ [other_level]
             in
             let other_idx = List.length new_levels - 1 in
             let remapping = Array.make (List.length levels) other_idx in
             List.iteri (fun old_idx level ->
               match List.find_index (( = ) level) kept_present with
               | Some new_idx -> remapping.(old_idx) <- new_idx
               | None -> ()
             ) levels;
             remap_factor_array arr levels ordered new_levels remapping
       | None, _, _ -> VVector arr
       | _, Error err, _ | _, _, Error err -> err)
  | _ -> Error.make_error Ast.ArityError "fct_other expects a factor vector"

let fct_drop_impl args _env =
  match args with
  | [VVector arr] ->
      (match find_first_factor_in_array arr with
       | Some (levels, ordered) ->
           let used = Array.make (List.length levels) false in
           Array.iter (function
             | VFactor (i, _, _) when i >= 0 && i < Array.length used -> used.(i) <- true
             | _ -> ()
           ) arr;
           let kept_levels =
             List.mapi (fun idx level -> (idx, level)) levels
             |> List.filter (fun (idx, _) -> used.(idx))
           in
           let new_levels = List.map snd kept_levels in
           let remapping = Array.make (List.length levels) (-1) in
           List.iteri (fun new_idx (old_idx, _) -> remapping.(old_idx) <- new_idx) kept_levels;
           remap_factor_array arr levels ordered new_levels remapping
       | None -> VVector arr)
  | _ -> Error.make_error Ast.ArityError "fct_drop expects 1 argument"

let fct_expand_impl (args : (string option * value) list) _env =
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
  let candidate_levels value =
    match value with
    | VString s -> [s]
    | VVector arr ->
        Array.fold_left (fun acc item ->
          match item with
          | VString s -> s :: acc
          | _ -> acc
        ) [] arr
        |> List.rev
    | VList items ->
        List.fold_left (fun acc (_, item) ->
          match item with
          | VString s -> s :: acc
          | _ -> acc
        ) [] items
        |> List.rev
    | _ -> []
  in
  match positional with
  | VVector arr :: extra_levels ->
      (match find_first_factor_in_array arr with
       | Some (levels, ordered) ->
           let new_levels =
             List.fold_left (fun acc value ->
               append_unique_levels acc (candidate_levels value)
             ) levels extra_levels
           in
           let remapping = Array.init (List.length levels) Fun.id in
           remap_factor_array arr levels ordered new_levels remapping
       | None -> VVector arr)
  | _ -> Error.make_error Ast.ArityError "fct_expand expects a factor vector and optional levels"

let fct_c_impl (args : (string option * value) list) _env =
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
  let extract_values value =
    match value with
    | VVector arr -> Array.to_list arr
    | VList items -> List.map snd items
    | scalar -> [scalar]
  in
  let labels_of_values values =
    List.map (function
      | VFactor (idx, levels, _) -> List.nth_opt levels idx
      | VString s -> Some s
      | VNA _ -> None
      | other -> Some (Utils.value_to_string other)
    ) values
  in
  match positional with
  | [] -> Error.make_error Ast.ArityError "fct_c expects at least one factor vector"
  | values ->
      let concatenated = List.concat_map extract_values values in
      let ordered =
        List.for_all (function
          | VVector arr ->
              (match find_first_factor_in_array arr with
               | Some (_, is_ordered) -> is_ordered
               | None -> true)
          | _ -> true) values
      in
      let unified_levels =
        List.fold_left (fun acc value ->
          let levels_to_add =
            match value with
            | VVector arr ->
                (match find_first_factor_in_array arr with
                 | Some (levels, _) -> levels
                 | None ->
                     labels_of_values (Array.to_list arr) |> List.filter_map Fun.id)
            | VList items ->
                labels_of_values (List.map snd items) |> List.filter_map Fun.id
            | scalar ->
                labels_of_values [scalar] |> List.filter_map Fun.id
          in
          append_unique_levels acc levels_to_add
        ) [] values
      in
      let remap = Hashtbl.create (List.length unified_levels) in
      List.iteri (fun idx level -> Hashtbl.replace remap level idx) unified_levels;
      let factor_values =
        labels_of_values concatenated
        |> List.map (function
             | None -> VNA Ast.NAGeneric
             | Some label ->
                 (match Hashtbl.find_opt remap label with
                  | Some idx -> VFactor (idx, unified_levels, ordered)
                  | None -> VNA Ast.NAGeneric))
      in
      VVector (Array.of_list factor_values)

let register env =
  let env = Env.add "factor" (make_builtin_named ~name:"factor" ~variadic:true 1 factor_impl) env in
  let env = Env.add "as_factor" (make_builtin_named ~name:"as_factor" ~variadic:true 1 as_factor_impl) env in
  let env = Env.add "fct_infreq" (make_builtin_named ~name:"fct_infreq" ~variadic:true 1 fct_infreq_impl) env in
  let env = Env.add "levels" (make_builtin ~name:"levels" 1 levels_impl) env in
  let env = Env.add "fct_rev" (make_builtin ~name:"fct_rev" 1 fct_rev_impl) env in
  let env = Env.add "fct_recode" (make_builtin_named ~name:"fct_recode" ~variadic:true 1 fct_recode_impl) env in
  let env = Env.add "fct_reorder" (make_builtin_named ~name:"fct_reorder" ~variadic:true 2 fct_reorder_impl) env in
  let env = Env.add "fct_lump_n" (make_builtin_named ~name:"fct_lump_n" ~variadic:true 1 fct_lump_n_impl) env in
  let env = Env.add "fct_lump_min" (make_builtin_named ~name:"fct_lump_min" ~variadic:true 2 fct_lump_min_impl) env in
  let env = Env.add "fct_lump_prop" (make_builtin_named ~name:"fct_lump_prop" ~variadic:true 2 fct_lump_prop_impl) env in
  let env = Env.add "fct" (make_builtin_named ~name:"fct" ~variadic:true 1 fct_impl) env in
  let env = Env.add "fct_relevel" (make_builtin_named ~name:"fct_relevel" ~variadic:true 1 fct_relevel_impl) env in
  let env = Env.add "fct_collapse" (make_builtin_named ~name:"fct_collapse" ~variadic:true 1 fct_collapse_impl) env in
  let env = Env.add "fct_other" (make_builtin_named ~name:"fct_other" ~variadic:true 1 fct_other_impl) env in
  let env = Env.add "fct_drop" (make_builtin ~name:"fct_drop" 1 fct_drop_impl) env in
  let env = Env.add "fct_expand" (make_builtin_named ~name:"fct_expand" ~variadic:true 1 fct_expand_impl) env in
  let env = Env.add "fct_c" (make_builtin_named ~name:"fct_c" ~variadic:true 1 fct_c_impl) env in
  let env = Env.add "ordered" (make_builtin_named ~name:"ordered" ~variadic:true 1 ordered_impl) env in
  env
