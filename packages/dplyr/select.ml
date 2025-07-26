(* dplyr.select.ml *)

open Ast

(* Helper to find columns by name, Symbol-based for NSE compatibility *)
let select_columns (table : value) (cols : symbol list) : value =
  match table with
  | Table t ->
      let selected =
        List.filter_map (fun name ->
          match List.assoc_opt name t.columns with
          | Some col_data -> Some (name, col_data)
          | None -> None
        ) cols
      in
      if List.length selected <> List.length cols then
        let missing = List.filter (fun name -> not (List.mem_assoc name t.columns)) cols in
        Error ("Column(s) not found: " ^ String.concat ", " missing)
      else
        Table { t with columns = selected }
  | _ -> Error "select expects a table"

(* select function receives Table as first arg, then bare Symbol column names *)
let select_function args =
  match args with
  | (Table _ as table) :: rest ->
      let col_names =
        List.fold_left (fun acc v ->
          match v with
          | Symbol s -> s :: acc
          | _ -> acc
        ) [] rest |> List.rev
      in
      if List.length col_names <> List.length rest then
        Error "select expects bare Symbol column names as arguments"
      else
        select_columns table col_names
  | _ -> Error "select expects a table as first argument"
