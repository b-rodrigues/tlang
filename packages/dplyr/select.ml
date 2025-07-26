(* dplyr.select.ml *)

open Ast

(* Helper: select columns from table by symbol *)
let select_column_by_symbol columns symbol =
  match List.assoc_opt symbol columns with
  | Some col_data -> Ok (symbol, col_data)
  | None -> Error ("Column not found: " ^ symbol)

(* Helper: select columns from table by 1-indexed position *)
let select_column_by_index columns idx =
  let n = List.length columns in
  if idx < 1 || idx > n then
    Error ("Column index out of bounds (1-indexed): " ^ string_of_int idx)
  else
    Ok (List.nth columns (idx - 1))

(* Helper: select elements from array/list by 1-indexed position *)
let select_element_by_index elements idx =
  let n = List.length elements in
  if idx < 1 || idx > n then
    Error ("Element index out of bounds (1-indexed): " ^ string_of_int idx)
  else
    Ok (List.nth elements (idx - 1))

(* Expand ranges like 2:6 to [2;3;4;5;6] *)
let rec expand_range v =
  match v with
  | Range (VInt start, VInt end_) ->
      let rec aux i acc =
        if i > end_ then List.rev acc
        else aux (i + 1) (VInt i :: acc)
      in
      aux start []
  | _ -> [v]

(* Flatten selectors, expanding ranges *)
let flatten_selectors selectors =
  List.flatten (List.map expand_range selectors)

let select_function args =
  match args with
  | (Table t as table) :: selectors ->
      let columns = t.columns in
      let selectors = flatten_selectors selectors in
      let rec gather acc errors = function
        | [] -> (List.rev acc, List.rev errors)
        | sel :: rest ->
            let res =
              match sel with
              | Symbol name -> select_column_by_symbol columns name
              | Int idx -> select_column_by_index columns idx
              | _ -> Error "select expects bare column names (symbol), integer positions, or integer ranges for tables"
            in
            begin match res with
            | Ok col -> gather (col :: acc) errors rest
            | Error e -> gather acc (e :: errors) rest
            end
      in
      let selected, errors = gather [] [] selectors in
      if errors <> [] then
        Error (String.concat "; " errors)
      else
        Table { t with columns = selected }
  | (Array arr) :: selectors
  | (List arr) :: selectors ->
      let selectors = flatten_selectors selectors in
      let rec gather acc errors = function
        | [] -> (List.rev acc, List.rev errors)
        | sel :: rest ->
            let res =
              match sel with
              | Int idx -> select_element_by_index arr idx
              | _ -> Error "select expects integer positions or integer ranges for arrays/lists"
            in
            begin match res with
            | Ok el -> gather (el :: acc) errors rest
            | Error e -> gather acc (e :: errors) rest
            end
      in
      let selected, errors = gather [] [] selectors in
      if errors <> [] then
        Error (String.concat "; " errors)
      else
        List selected
  | _ -> Error "select expects a table, array, or list as first argument"
