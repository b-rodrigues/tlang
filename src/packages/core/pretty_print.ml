open Ast

(** Internal helper to format cell values *)
let cell_to_string v =
  match v with
  | VString s -> s
  | VNA na_t ->
      let tag = Utils.na_type_to_string na_t in
      if tag = "" then "NA" else "NA(" ^ tag ^ ")"
  | VFloat f ->
      if f = floor f then Printf.sprintf "%.1f" f
      else if Float.abs f < 0.001 then Printf.sprintf "%.4e" f
      else Printf.sprintf "%.4g" f
  | other -> Utils.value_to_string other

(** Pretty-print a DataFrame as a table *)
let pretty_print_dataframe ?(headers) { arrow_table; group_keys } =
  let nrows = Arrow_table.num_rows arrow_table in
  let value_columns = Arrow_bridge.table_to_value_columns arrow_table in
  if value_columns = [] then
    "Empty DataFrame (0 rows x 0 cols)\n"
  else
    let col_names = match headers with
      | Some h -> List.map (fun (old_n, _) -> match List.assoc_opt old_n h with Some new_n -> new_n | None -> old_n) value_columns
      | None -> List.map fst value_columns in
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
let pretty_print_error { code; message; context; location; na_count = _ } =
  let buf = Buffer.create 128 in
  let rendered_message =
    match location with
    | Some { file; line; column } ->
        let prefix =
          match file with
          | Some filename -> Printf.sprintf "[%s:L%d:C%d]" filename line column
          | None -> Printf.sprintf "[L%d:C%d]" line column
        in
        prefix ^ " " ^ message
    | None -> message
  in
  Buffer.add_string buf (Printf.sprintf "Error(%s): %s\n"
    (Utils.error_code_to_string code) rendered_message);
  if context <> [] then begin
    Buffer.add_string buf "  Context:\n";
    List.iter (fun (k, v) ->
      Buffer.add_string buf (Printf.sprintf "    %s: %s\n" k (Utils.value_to_string v))
    ) context
  end;
  Buffer.contents buf

(** Pretty-print a pipeline *)
let pretty_print_pipeline { p_nodes; p_deps; p_runtimes; _ } =
  let buf = Buffer.create 256 in
  Buffer.add_string buf (Printf.sprintf "Pipeline (%d nodes):\n" (List.length p_nodes));
  List.iter (fun (name, v) ->
    let deps = match List.assoc_opt name p_deps with
      | Some d when d <> [] -> Printf.sprintf " [depends: %s]" (String.concat ", " d)
      | _ -> ""
    in
    let runtime = match List.assoc_opt name p_runtimes with
      | Some r when r <> "T" -> Printf.sprintf " [%s]" r
      | _ -> ""
    in
    let val_str = match v with
      | VDataFrame { arrow_table; _ } ->
          Printf.sprintf "DataFrame(%d rows x %d cols)"
            (Arrow_table.num_rows arrow_table) (Arrow_table.num_columns arrow_table)
      | _ -> Utils.value_to_string v
    in
    Buffer.add_string buf (Printf.sprintf "  %s = %s%s%s\n" name val_str runtime deps)
  ) p_nodes;
  Buffer.contents buf

(** Pretty-print a model summary *)
let pretty_print_summary pairs =
  let model_class = match List.assoc_opt "model_class" pairs with Some (VString s) -> s | _ -> "lm" in
  let summary_type = match List.assoc_opt "summary_type" pairs with Some (VString s) -> s | _ -> "coefficients" in
  let is_glm = model_class = "glm" in
  let family = match List.assoc_opt "family" pairs with Some (VString s) -> s | Some v -> Utils.value_to_string v | None -> "Gaussian" in
  let link = match List.assoc_opt "link" pairs with Some (VString s) -> s | Some v -> Utils.value_to_string v | None -> "identity" in
  let buf = Buffer.create 256 in
  if is_glm then begin
    Buffer.add_string buf (Printf.sprintf "Family:   %s\n" family);
    Buffer.add_string buf (Printf.sprintf "Link:     %s\n\n" link)
  end;
  Buffer.add_string buf (if summary_type = "fit_stats" then "Model metrics:\n" else "Coefficients:\n");
  (match List.assoc_opt "_tidy_df" pairs with
  | Some (VDataFrame df) ->
      if summary_type = "fit_stats" then
        Buffer.add_string buf (pretty_print_dataframe df)
      else
        let headers = [
          ("term", "");
          ("estimate", "Estimate");
          ("std_error", "Std. Error");
          ("statistic", if is_glm then "z value" else "t value");
          ("p_value", if is_glm then "Pr(>|z|)" else "Pr(>|t|)")
        ] in
        Buffer.add_string buf (pretty_print_dataframe ~headers df)
  | _ -> Buffer.add_string buf "No coefficient data available.\n");
  Buffer.contents buf

let is_visual_metadata_class = function
  | VString "ggplot" | VString "matplotlib" | VString "plotnine" | VString "seaborn" | VString "plotly" | VString "altair" | VString "bokeh" -> true
  | _ -> false

let display_keys_from_pairs pairs =
  List.fold_left (fun acc (k, v) ->
    match k, v with
    | "_display_keys", VList items ->
        Some (List.filter_map (fun (_, v) -> match v with VString s -> Some s | _ -> None) items)
    | _ -> acc
  ) None pairs

(** Internal helper for recursive pretty formatting with indentation *)
let rec pretty_format ?(max_depth=5) ?(indent="") v =
  match v with
  | VDict pairs ->
      if max_depth <= 0 then Utils.value_to_string v
      else if pairs = [] then "{}" else
      let display_keys = display_keys_from_pairs pairs in
      let visible_pairs = match display_keys with
        | None -> pairs
        | Some keys -> List.filter (fun (k, _) -> List.mem k keys) pairs
      in
      if visible_pairs = [] then "{}" else
      let next_indent = indent ^ "  " in
      let lines = List.map (fun (k, v) ->
        Printf.sprintf "%s`%s`: %s" next_indent k (pretty_format ~max_depth:(max_depth - 1) ~indent:next_indent v)
      ) visible_pairs in
      "{\n" ^ String.concat ",\n" lines ^ "\n" ^ indent ^ "}"
  | VList items ->
      if max_depth <= 0 then Utils.value_to_string v
      else if items = [] then "[]" else
      let next_indent = indent ^ "  " in
      let lines = List.map (fun (_, v) ->
         pretty_format ~max_depth:(max_depth - 1) ~indent:next_indent v
      ) items in
      let all_simple = List.length items <= 5 && List.for_all (fun (_, v) ->
        match v with VDict _ | VList _ | VVector _ | VDataFrame _ | VPipeline _ -> false | _ -> true
       ) items in
       if all_simple then Utils.value_to_string v
       else "[\n" ^ indent ^ "  " ^ String.concat (",\n" ^ indent ^ "  ") lines ^ "\n" ^ indent ^ "]"
   | other -> Utils.value_to_string other

and pretty_print_visual_metadata pairs =
  let visible_pairs =
    pairs
    |> List.filter (fun (k, _) -> k <> "_display_keys")
  in
  let class_name =
    match List.assoc_opt "class" visible_pairs with
    | Some (VString s) -> s
    | _ -> "plot"
  in
  let body_pairs =
    visible_pairs
    |> List.filter (fun (k, _) -> k <> "class")
  in
  if body_pairs = [] then
    Printf.sprintf "%s {}\n" class_name
  else
    let display_keys =
      match display_keys_from_pairs pairs with
      | Some keys ->
          let body_key_set =
            List.fold_left (fun acc (k, _) -> String_set.add k acc) String_set.empty body_pairs
          in
          List.filter (fun key -> String_set.mem key body_key_set) keys
      | None -> List.map fst body_pairs
    in
    let display_key_set =
      List.fold_left (fun acc key -> String_set.add key acc) String_set.empty display_keys
    in
    let filtered_body_pairs =
      List.filter (fun (k, _) -> String_set.mem k display_key_set) body_pairs
    in
    let body =
      pretty_format
        (VDict (filtered_body_pairs @ [("_display_keys", VList (List.map (fun k -> (None, VString k)) display_keys))]))
    in
    Printf.sprintf "%s %s\n" class_name body

(** Pretty-print any value for REPL display *)
let pretty_print_value v =
  match v with
  | VDataFrame df -> pretty_print_dataframe df
  | VError err -> pretty_print_error err
  | VPipeline p -> pretty_print_pipeline p
  | VDict pairs ->
      let is_summary = List.mem_assoc "class" pairs && List.assoc "class" pairs = VString "summary" in
      let is_visual_metadata =
        List.mem_assoc "class" pairs
        && is_visual_metadata_class (List.assoc "class" pairs)
      in
      let has_kind = List.mem_assoc "kind" pairs in
      let is_large = List.length pairs > 5 in
      let has_nested = List.exists (fun (_, v) -> match v with VDict _ | VList _ | VVector _ -> true | _ -> false) pairs in
      if is_summary then
        pretty_print_summary pairs
      else if is_visual_metadata then
        pretty_print_visual_metadata pairs
      else if has_kind || is_large || has_nested then
        pretty_format v ^ "\n"
      else
        Utils.value_to_string v ^ "\n"
  | VList _ -> pretty_format v ^ "\n"
  | VNA _ -> ""
  | other -> Utils.value_to_string other ^ "\n"

(** Register pretty_print as a builtin function *)
(*
--# Pretty-print a value
--#
--# Prints a formatted representation of a value. DataFrames are printed as tables.
--#
--# @name pretty_print
--# @param x :: Any The value to print.
--# @return :: Null
--# @example
--#   pretty_print(df)
--# @family core
--# @seealso print
--# @export
*)
let register env =
  Env.add "pretty_print"
    (make_builtin ~name:"pretty_print" 1 (fun args _env ->
      match args with
      | [v] ->
          print_string (pretty_print_value v);
          (VNA NAGeneric)
      | _ -> Error.arity_error_named "pretty_print" 1 (List.length args)
    ))
    env
