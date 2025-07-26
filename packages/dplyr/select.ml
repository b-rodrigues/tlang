(* dplyr.select.ml *)

open Ast

let select_columns_by_name (columns : (string * value) list) (name : string) : (string * value, string) result =
  match List.assoc_opt name columns with
  | Some col_data -> Ok (name, col_data)
  | None -> Error ("Column not found: " ^ name)

let select_columns_by_index (columns : (string * value) list) (idx : int) : (string * value, string) result =
  let n = List.length columns in
  if idx < 1 || idx > n then
    Error ("Column index out of bounds (1-indexed): " ^ string_of_int idx)
  else
    Ok (List.nth columns (idx - 1))

let select_columns (table : value) (selectors : value list) : value =
  match table with
  | Table t ->
      let columns = t.columns in
      let rec gather acc errors = function
        | [] -> (List.rev acc, List.rev errors)
        | sel :: rest ->
            let res =
              match sel with
              | Symbol name -> select_columns_by_name columns name
              | Int idx -> select_columns_by_index columns idx
              | _ -> Error "select expects column names or integer positions"
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
  | _ -> Error "select expects a table"

let select_function args =
  match args with
  | (Table _ as table) :: selectors ->
      if selectors = [] then
        Error "select expects at least one column selector"
      else
        select_columns table selectors
  | _ -> Error "select expects a table as first argument"
