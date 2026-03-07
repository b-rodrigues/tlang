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

let factor_impl (args : (string option * value) list) _env =
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
      let unique_levels = List.sort_uniq String.compare non_na_strings in

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

let as_factor_impl args env =
  factor_impl args env

let fct_infreq_impl args _env =
  let positional = List.filter_map (fun (k, v) -> if k = None then Some v else None) args in
  match positional with
  | [VVector arr] ->
      let factors = Array.to_list arr in
      let c, levels, ordered = match factors with
        | VFactor (_, l, o) :: _ -> true, l, o
        | _ -> false, [], false
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

let register env =
  let env = Env.add "factor" (make_builtin_named ~name:"factor" ~variadic:true 1 factor_impl) env in
  let env = Env.add "as_factor" (make_builtin_named ~name:"as_factor" ~variadic:true 1 as_factor_impl) env in
  let env = Env.add "fct_infreq" (make_builtin_named ~name:"fct_infreq" ~variadic:true 1 fct_infreq_impl) env in
  env
