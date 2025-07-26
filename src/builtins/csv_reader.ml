(* src/builtins/csv_reader.ml *)

open Ast

let read_csv (filename : string) : value =
  try
    let ic = open_in filename in
    let csv = Csv.of_channel ic in
    let rows = Csv.input_all csv in
    close_in ic;
    match rows with
    | [] -> VError "CSV is empty"
    | header :: data ->
        let columns =
          List.mapi
            (fun col_idx col_name ->
              let col_data =
                List.map
                  (fun row ->
                    try VString (List.nth row col_idx) (* CSV is 0-indexed internally, keep for reading *)
                    with _ -> VNull)
                  data
              in
              (col_name, VList col_data))
            header
        in
        VTable columns
  with
  | Sys_error msg -> VError ("File error: " ^ msg)
  | e -> VError ("CSV read error: " ^ Printexc.to_string e) 

(* If you add more user-facing column/row selection built-ins, ensure those are 1-indexed for user calls, even if the internal CSV logic stays 0-indexed *)
