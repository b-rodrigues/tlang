(* dplyr.select.ml *)

open Ast

(* Helper to find columns by name *)
let select_columns (table : value) (cols : string list) : value =
  match table with
  | VTable columns ->
      let selected =
        List.fold_left
          (fun acc name ->
             match List.assoc_opt name columns with
             | Some col_data -> (name, col_data) :: acc
             | None -> raise (Failure ("Column not found: " ^ name)))
          []
          cols
      in
      VTable (List.rev selected)
  | _ -> VError "select expects a table"

(* select function receives VTable first arg, then bare column names *)
let select_function args =
  match args with
  | (VTable _ as table) :: rest ->
      let col_names =
        List.fold_left (fun acc v ->
          match v with
          | VName s -> s :: acc
          | _ -> raise (Failure "select expects bare column names")
        ) [] rest |> List.rev
      in
      (try select_columns table col_names
       with Failure msg -> VError msg)
  | _ -> VError "select expects a table as first argument"
 
