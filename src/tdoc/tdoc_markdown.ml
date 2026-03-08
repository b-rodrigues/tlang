(* src/tdoc/tdoc_markdown.ml *)
(* Markdown generator for T-Doc *)

open Tdoc_types

let normalize_named_argument_syntax (line : string) : string =
  let len = String.length line in
  let buf = Buffer.create len in
  let is_ident_start = function
    | 'a' .. 'z' | 'A' .. 'Z' | '_' -> true
    | _ -> false
  in
  let is_ident_char = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
    | _ -> false
  in
  let rec copy_ident j =
    if j < len && is_ident_char line.[j] then copy_ident (j + 1) else j
  in
  let rec skip_spaces j =
    if j < len && line.[j] = ' ' then skip_spaces (j + 1) else j
  in
  let rec prev_non_space j =
    if j < 0 then None
    else if line.[j] = ' ' then prev_non_space (j - 1)
    else Some line.[j]
  in
  let rec loop i =
    if i >= len then ()
    else if is_ident_start line.[i] then begin
      let j = copy_ident (i + 1) in
      let k = skip_spaces j in
      let prev = prev_non_space (i - 1) in
      if k < len && line.[k] = ':' && (prev = Some '(' || prev = Some ',') then begin
        Buffer.add_substring buf line i (j - i);
        Buffer.add_string buf " = ";
        loop (skip_spaces (k + 1))
      end else begin
        Buffer.add_substring buf line i (j - i);
        loop j
      end
    end else begin
      Buffer.add_char buf line.[i];
      loop (i + 1)
    end
  in
  loop 0;
  Buffer.contents buf

let generate_function_doc entry =
  let buf = Buffer.create 1024 in
  Printf.bprintf buf "# %s\n\n" entry.name;
  
  if entry.description_brief <> "" then
    Printf.bprintf buf "%s\n\n" entry.description_brief;
    
  if entry.description_full <> "" then
    Printf.bprintf buf "%s\n\n" entry.description_full;
    
  if entry.params <> [] then begin
    Printf.bprintf buf "## Parameters\n\n";
    List.iter (fun (p : param_doc) ->
      let type_str = match p.type_info with Some t -> " (`" ^ t ^ "`)" | None -> "" in
      Printf.bprintf buf "- **%s**%s: %s\n\n" p.name type_str p.description
    ) entry.params;
    Buffer.add_string buf "\n";
  end;
  
  begin match entry.return_value with
  | Some r ->
      Printf.bprintf buf "## Returns\n\n";
      Printf.bprintf buf "%s\n\n" r.description
  | None -> ()
  end;
  
  if entry.examples <> [] then begin
    Printf.bprintf buf "## Examples\n\n```t\n";
    List.iter (fun e -> Printf.bprintf buf "%s\n" (normalize_named_argument_syntax e)) entry.examples;
    Printf.bprintf buf "```\n\n";
  end;
  
  if entry.see_also <> [] then begin
    Printf.bprintf buf "## See Also\n\n";
    let links = List.map (fun s -> Printf.sprintf "[%s](%s.html)" s s) entry.see_also in
    Printf.bprintf buf "%s\n\n" (String.concat ", " links);
  end;
  
  Buffer.contents buf

let generate_index entries =
  let buf = Buffer.create 1024 in
  Printf.bprintf buf "# Function Reference\n\n";
  
  Printf.bprintf buf "| Function | Description |\n";
  Printf.bprintf buf "| --- | --- |\n";
  
  List.iter (fun e ->
    if e.is_export then
      Printf.bprintf buf "| [%s](%s.html) | %s |\n" e.name e.name e.description_brief
  ) (List.sort (fun a b -> String.compare a.name b.name) entries);
  
  Buffer.contents buf
