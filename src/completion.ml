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
    if !in_comment then () (* once in comment on this line, stays till cursor (heuristic for repl) *)
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
  (* 1. Check for member completion: ident. *)
  let member_match = 
    let find_dot i =
      if i < 0 then None
      else if buffer.[i] = '.' then
        let start = ref (i - 1) in
        while !start >= 0 && is_ident_char buffer.[!start] do
          start := !start - 1
        done;
        let ident = String.sub buffer (!start + 1) (i - !start - 1) in
        if ident <> "" then Some ident else None
      else None
    in
    if cursor > 0 && buffer.[cursor-1] = '.' then find_dot (cursor-1) else None
  in

  (* 2. Check for function argument hints: ident( *)
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

  match member_match with
  | Some ident ->
      (match lookup scope ident with
      | Some { typ = Some (Semantic_type.TDataFrame cols); _ }
      | Some { typ = Some (Semantic_type.TGroupedDataFrame (cols, _)); _ } ->
          List.map (fun (c : Semantic_type.column) -> ident ^ "." ^ c.name) cols
      | _ -> [])
  | None ->
    (match function_match with
    | Some ident ->
        (match lookup scope ident with
        | Some { typ = Some (Semantic_type.TFunction (args, _)); _ } ->
            List.map (fun (name, _) -> buffer ^ name ^ " = ") args
        | _ -> [])
    | None ->
        (* 3. Standard prefix completion *)
        let prefix = extract_prefix buffer cursor in
        if prefix = "" then []
        else
          all scope
          |> List.filter (fun s -> String.starts_with ~prefix s.name)
          |> List.map (fun s -> s.name)
          |> List.sort_uniq String.compare)


