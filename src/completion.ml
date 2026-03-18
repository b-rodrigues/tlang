(* src/completion.ml *)

open Symbol_table

let is_ident_char = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> true
  | _ -> false


let is_inside_comment_or_string buffer cursor =
  let in_string = ref false in
  let string_char = ref '"' in
  let in_comment = ref false in
  let i = ref 0 in
  while !i < cursor do
    let c = buffer.[!i] in
    if !in_comment then ()
    else if !in_string then (
      if c = '\\' && !i + 1 < cursor then i := !i + 1
      else if c = !string_char then in_string := false
    ) else (
      if c = '"' || c = '\'' then (in_string := true; string_char := c)
      else if c = '-' && !i + 1 < cursor && buffer.[!i+1] = '-' then in_comment := true
    );
    i := !i + 1
  done;
  !in_string || !in_comment

let extract_prefix buffer cursor =
  if is_inside_comment_or_string buffer cursor then ""
  else (
    let pos = ref (cursor - 1) in
    while !pos >= 0 && is_ident_char buffer.[!pos] do
      pos := !pos - 1
    done;
    String.sub buffer (!pos + 1) (cursor - !pos - 1)
  )


let collect_all_columns scope cols =
  let df_cols = List.map (fun (c : Semantic_type.column) -> c.Semantic_type.name) cols in
  let observed = Symbol_table.get_observed_columns scope in
  List.sort_uniq String.compare (df_cols @ observed)

let complete scope ~buffer ~cursor =
  if is_inside_comment_or_string buffer cursor then (cursor, [])
  else begin
  (* Scan backwards from cursor to the start of the current identifier *)
  let id_start = ref (cursor - 1) in
  while !id_start >= 0 && is_ident_char buffer.[!id_start] do
    id_start := !id_start - 1
  done;
  let id_boundary = !id_start in

  (* 1. Member completion: ident.member_prefix — only when '.' precedes the identifier *)
  if id_boundary >= 0 && buffer.[id_boundary] = '.' then begin
    let dot_pos = id_boundary in
    let member_prefix = String.sub buffer (dot_pos + 1) (cursor - dot_pos - 1) in
    let istart = ref (dot_pos - 1) in
    while !istart >= 0 && is_ident_char buffer.[!istart] do
      istart := !istart - 1
    done;
    let ident = String.sub buffer (!istart + 1) (dot_pos - !istart - 1) in
    if ident <> "" then
      match lookup scope ident with
      | Some { typ = Some (Semantic_type.TDataFrame cols); _ }
      | Some { typ = Some (Semantic_type.TGroupedDataFrame (cols, _)); _ } ->
          let all_cols = collect_all_columns scope cols in
          let matches = List.filter (fun name -> String.starts_with ~prefix:member_prefix name) all_cols in
          (dot_pos + 1, matches)
      | _ -> (dot_pos + 1, [])
    else (dot_pos + 1, [])

  (* 2. Function argument completion: func( — only when cursor is right after '(' *)
  end else if cursor > 0 && buffer.[cursor-1] = '(' then begin
    let paren_pos = cursor - 1 in
    let fstart = ref (paren_pos - 1) in
    while !fstart >= 0 && is_ident_char buffer.[!fstart] do
      fstart := !fstart - 1
    done;
    let ident = String.sub buffer (!fstart + 1) (paren_pos - !fstart - 1) in
    if ident <> "" then
      match lookup scope ident with
      | Some { typ = Some (Semantic_type.TFunction (args, _)); _ } ->
          (cursor, List.map (fun (name, _) -> name ^ " = ") args)
      | _ -> (cursor, [])
    else (cursor, [])

  (* 3. Column reference completion: $col_prefix *)
  end else if id_boundary >= 0 && buffer.[id_boundary] = '$' then begin
    let col_prefix = String.sub buffer (id_boundary + 1) (cursor - id_boundary - 1) in
    let observed = Symbol_table.get_observed_columns scope in
    let df_cols = Symbol_table.get_dataframes scope |> List.filter_map (fun s ->
      match s.typ with
      | Some (Semantic_type.TDataFrame cols)
      | Some (Semantic_type.TGroupedDataFrame (cols, _)) -> Some (List.map (fun (c: Semantic_type.column) -> c.Semantic_type.name) cols)
      | _ -> None
    ) |> List.flatten in
    let all_cols = List.sort_uniq String.compare (df_cols @ observed) in
    let matches = List.filter (fun name -> String.starts_with ~prefix:col_prefix name) all_cols in
    (id_boundary + 1, matches)

  (* 4. Symbol/identifier completion *)
  end else begin
    let prefix = String.sub buffer (id_boundary + 1) (cursor - id_boundary - 1) in
    if prefix = "" then (cursor, [])
    else
      let start = cursor - String.length prefix in
      let matches = Symbol_table.filter_symbols scope prefix
                    |> List.map (fun s -> s.Symbol_table.name) in
      (start, matches)
  end
  end
