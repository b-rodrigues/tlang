(* src/packages/core/read_csv.ml *)
(* Defines the 'read_csv' built-in function for the T language. *)

open Ast
open Eval_helpers

(**
 * This is the raw OCaml implementation of the function.
 * It takes a list of evaluated arguments from the T runtime.
 *)
let read_csv_impl (args: value list) (_env: environment) : value =
  match args with
  | [VString path] ->
      (try
        let csv_data = Csv.load path in
        match csv_data with
        | [] -> make_dataframe [] [] (* Return an empty but valid DataFrame *)
        | header :: data ->
            (* Csv.transpose is a clean way to get columns *)
            let columns_as_rows = Csv.transpose (header :: data) in
            let column_names = List.map List.hd columns_as_rows in
            let column_values =
              List.map
                (fun (_hd :: tail) -> Array.of_list (List.map (fun s -> VString s) tail))
                columns_as_rows
            in
            make_dataframe column_names column_values
      with
      | Sys_error msg -> Error ("File Error: " ^ msg)
      | _ -> Error "CSV Error: Failed to parse the CSV file. It may be malformed.")
  | [other] -> type_error "String for the path" other
  | _ -> Error "Arity Error: read_csv() takes exactly 1 argument"

(**
 * This is the public value exposed by this module.
 * It's a VBuiltin that wraps our OCaml implementation.
 *)
let v = make_native_fn 1 read_csv_impl
