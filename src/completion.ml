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
  if is_inside_comment_or_string buffer cursor then []
  else begin
  (* 1. Check for member completion: ident[.|$][member_prefix] *)
  let member_match =
    let mstart = ref (cursor - 1) in
    while !mstart >= 0 && is_ident_char buffer.[!mstart] do
      mstart := !mstart - 1
    done;
    if !mstart >= 0 && (buffer.[!mstart] = '.' || buffer.[!mstart] = '$') then begin
      let sep = buffer.[!mstart] in
      let dot_pos = !mstart in
      let member_prefix = String.sub buffer (dot_pos + 1) (cursor - dot_pos - 1) in
      let istart = ref (dot_pos - 1) in
      while !istart >= 0 && is_ident_char buffer.[!istart] do
        istart := !istart - 1
      done;
      let ident = String.sub buffer (!istart + 1) (dot_pos - !istart - 1) in
      if ident <> "" then Some (ident, member_prefix, dot_pos + 1, sep)
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
 
  match member_match with
  | Some (ident, member_prefix, member_start, _sep) ->
      (match lookup scope ident with
      | Some { typ = Some (Semantic_type.TDataFrame cols); _ }
      | Some { typ = Some (Semantic_type.TGroupedDataFrame (cols, _)); _ } ->
          let buf_prefix = String.sub buffer 0 member_start in
          let df_cols = List.map (fun (c : Semantic_type.column) -> c.Semantic_type.name) cols in
          let observed = Symbol_table.get_observed_columns scope in
          let all_cols = List.sort_uniq String.compare (df_cols @ observed) in
          List.filter_map (fun name ->
            if String.starts_with ~prefix:member_prefix name then
              Some (buf_prefix ^ name)
            else None
          ) all_cols
      | _ -> [])
  | None ->
    (match function_match with
    | Some ident ->
        (match lookup scope ident with
        | Some { typ = Some (Semantic_type.TFunction (args, _)); _ } ->
            List.map (fun (name, _) -> buffer ^ name ^ " = ") args
        | _ -> [])
    | None ->
        (match column_prefix_match with
        | Some (col_prefix, col_start) ->
            let buf_prefix = String.sub buffer 0 col_start in
            let all_symbols = all scope in
            let df_cols = List.filter_map (fun s -> 
              match s.typ with
              | Some (Semantic_type.TDataFrame cols) 
              | Some (Semantic_type.TGroupedDataFrame (cols, _)) -> Some (List.map (fun (c: Semantic_type.column) -> c.Semantic_type.name) cols)
              | _ -> None
            ) all_symbols |> List.flatten in
            
            let observed = Symbol_table.get_observed_columns scope in
            let all_cols = List.sort_uniq String.compare (df_cols @ observed) in

            all_cols
            |> List.filter (fun name -> String.starts_with ~prefix:col_prefix name)
            |> List.map (fun name -> buf_prefix ^ name)
            |> List.sort_uniq String.compare
        | None ->
            let prefix = extract_prefix buffer cursor in
            if prefix = "" then []
            else
              let buf_prefix = String.sub buffer 0 (cursor - String.length prefix) in
              all scope
              |> List.filter (fun s -> String.starts_with ~prefix s.name)
              |> List.map (fun s -> buf_prefix ^ s.name)
              |> List.sort_uniq String.compare))
  end
