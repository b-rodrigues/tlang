(* src/packages/core/pretty_print.ml *)
(* Phase 7: Pretty-printing for REPL output *)

open Ast

(** Pretty-print a DataFrame as a table *)
let pretty_print_dataframe { arrow_table; group_keys } =
  let nrows = Arrow_table.num_rows arrow_table in
  let value_columns = Arrow_bridge.table_to_value_columns arrow_table in
  if value_columns = [] then
    "Empty DataFrame (0 rows x 0 cols)\n"
  else
    let col_names = List.map fst value_columns in
    (* Format each cell value *)
    let cell_to_string v =
      match v with
      | VString s -> s
      | VNA na_t ->
          let tag = Utils.na_type_to_string na_t in
          if tag = "" then "NA" else "NA(" ^ tag ^ ")"
      | other -> Utils.value_to_string other
    in
    (* Compute column widths *)
    let col_widths = List.map (fun (name, col_data) ->
      let header_len = String.length name in
      let max_data_len = Array.fold_left (fun acc v ->
        max acc (String.length (cell_to_string v))
      ) 0 col_data in
      max header_len max_data_len
    ) value_columns in
    let buf = Buffer.create 256 in
    (* Header *)
    let header_parts = List.map2 (fun name width ->
      Printf.sprintf "%-*s" width name
    ) col_names col_widths in
    Buffer.add_string buf ("  " ^ String.concat "  " header_parts ^ "\n");
    (* Separator *)
    let sep_parts = List.map (fun width ->
      String.make width '-'
    ) col_widths in
    Buffer.add_string buf ("  " ^ String.concat "  " sep_parts ^ "\n");
    (* Data rows — show at most 20 rows *)
    let display_rows = min nrows 20 in
    for row_idx = 0 to display_rows - 1 do
      let row_parts = List.map2 (fun (_name, col_data) width ->
        let v = col_data.(row_idx) in
        Printf.sprintf "%-*s" width (cell_to_string v)
      ) value_columns col_widths in
      Buffer.add_string buf ("  " ^ String.concat "  " row_parts ^ "\n")
    done;
    if nrows > 20 then
      Buffer.add_string buf (Printf.sprintf "  ... (%d more rows)\n" (nrows - 20));
    (* Footer *)
    let group_info = if group_keys = [] then ""
      else Printf.sprintf " grouped by [%s]" (String.concat ", " group_keys) in
    Buffer.add_string buf (Printf.sprintf "DataFrame: %d rows x %d cols%s\n"
      nrows (List.length value_columns) group_info);
    Buffer.contents buf

(** Pretty-print an error value *)
let pretty_print_error { code; message; context } =
  let buf = Buffer.create 128 in
  Buffer.add_string buf (Printf.sprintf "Error(%s): %s\n"
    (Utils.error_code_to_string code) message);
  if context <> [] then begin
    Buffer.add_string buf "  Context:\n";
    List.iter (fun (k, v) ->
      Buffer.add_string buf (Printf.sprintf "    %s: %s\n" k (Utils.value_to_string v))
    ) context
  end;
  Buffer.contents buf

(** Pretty-print a pipeline *)
let pretty_print_pipeline { p_nodes; p_deps; _ } =
  let buf = Buffer.create 256 in
  Buffer.add_string buf (Printf.sprintf "Pipeline (%d nodes):\n" (List.length p_nodes));
  List.iter (fun (name, v) ->
    let deps = match List.assoc_opt name p_deps with
      | Some d when d <> [] -> Printf.sprintf " [depends: %s]" (String.concat ", " d)
      | _ -> ""
    in
    let val_str = match v with
      | VDataFrame { arrow_table; _ } ->
          Printf.sprintf "DataFrame(%d rows x %d cols)"
            (Arrow_table.num_rows arrow_table) (Arrow_table.num_columns arrow_table)
      | _ -> Utils.value_to_string v
    in
    Buffer.add_string buf (Printf.sprintf "  %s = %s%s\n" name val_str deps)
  ) p_nodes;
  Buffer.contents buf

(** Pretty-print any value for REPL display *)
let pretty_print_value v =
  match v with
  | VDataFrame df -> pretty_print_dataframe df
  | VError err -> pretty_print_error err
  | VPipeline p -> pretty_print_pipeline p
  | VNull -> ""
  | other -> Utils.value_to_string other ^ "\n"

(** Register pretty_print as a builtin function *)
let register env =
  Env.add "pretty_print"
    (make_builtin 1 (fun args _env ->
      match args with
      | [v] ->
          print_string (pretty_print_value v);
          VNull
      | _ -> make_error ArityError "pretty_print() takes exactly 1 argument"
    ))
    env
