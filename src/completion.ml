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


let complete scope ~buffer ~cursor =
  if is_inside_comment_or_string buffer cursor then (cursor, [])
  else begin
  (* 1. Check for member completion: ident.member_prefix *)
  let member_match =
    let mstart = ref (cursor - 1) in
    while !mstart >= 0 && is_ident_char buffer.[!mstart] do
      mstart := !mstart - 1
    done;
    if !mstart >= 0 && buffer.[!mstart] = '.' then begin
      let dot_pos = !mstart in
      let member_prefix = String.sub buffer (dot_pos + 1) (cursor - dot_pos - 1) in
      let istart = ref (dot_pos - 1) in
      while !istart >= 0 && is_ident_char buffer.[!istart] do
        istart := !istart - 1
      done;
      let ident = String.sub buffer (!istart + 1) (dot_pos - !istart - 1) in
      if ident <> "" then Some (ident, member_prefix, dot_pos + 1)
      else None
    end else None
  in
 
  let function_match =
    let find_paren i =
      if i < 0 then None
      else if buffer.[i] = '(' then
        let start = ref (i - 1) in
        while !start >= 0 && is_ident_char buffer.[!start] do
          start := !start - 1
        done;
        let ident = String.sub buffer (!start + 1) (i - !start - 1) in
        if ident <> "" then Some ident else None
      else None
    in
    if cursor > 0 && buffer.[cursor-1] = '(' then find_paren (cursor-1) else None
  in

  let column_prefix_match =
    let pstart = ref (cursor - 1) in
    while !pstart >= 0 && is_ident_char buffer.[!pstart] do
      pstart := !pstart - 1
    done;
    if !pstart >= 0 && buffer.[!pstart] = '$' then
      let prefix = String.sub buffer (!pstart + 1) (cursor - !pstart - 1) in
      Some (prefix, !pstart + 1)
    else None
  in
 
  let symbol_prefix_match =
    let prefix = extract_prefix buffer cursor in
    if prefix = "" then None
    else Some (prefix, cursor - String.length prefix)
  in

  match member_match with
  | Some (_ident, member_prefix, member_start) ->
      (match lookup scope _ident with
      | Some { typ = Some (Semantic_type.TDataFrame cols); _ }
      | Some { typ = Some (Semantic_type.TGroupedDataFrame (cols, _)); _ } ->
          let df_cols = List.map (fun (c : Semantic_type.column) -> c.Semantic_type.name) cols in
          let observed = Symbol_table.get_observed_columns scope in
          let all_cols = List.sort_uniq String.compare (df_cols @ observed) in
          let matches = List.filter (fun name -> String.starts_with ~prefix:member_prefix name) all_cols in
          (member_start, matches)
      | _ -> (member_start, []))
  | None ->
    (match function_match with
    | Some ident ->
        (match lookup scope ident with
        | Some { typ = Some (Semantic_type.TFunction (args, _)); _ } ->
            (cursor, List.map (fun (name, _) -> name ^ " = ") args)
        | _ -> (cursor, []))
    | None ->
        (match column_prefix_match with
        | Some (col_prefix, col_start) ->
            let observed = Symbol_table.get_observed_columns scope in
            let df_cols = Symbol_table.get_dataframes scope |> List.filter_map (fun s -> 
              match s.typ with
              | Some (Semantic_type.TDataFrame cols) 
              | Some (Semantic_type.TGroupedDataFrame (cols, _)) -> Some (List.map (fun (c: Semantic_type.column) -> c.Semantic_type.name) cols)
              | _ -> None
            ) |> List.flatten in
            let all_cols = List.sort_uniq String.compare (df_cols @ observed) in
            let matches = List.filter (fun name -> String.starts_with ~prefix:col_prefix name) all_cols in
            (col_start, matches)
        | None ->
            (match symbol_prefix_match with
            | Some (prefix, start) ->
                let matches = Symbol_table.filter_symbols scope prefix 
                              |> List.map (fun s -> s.Symbol_table.name) in
                (start, matches)
            | None -> (cursor, []))))
  end
