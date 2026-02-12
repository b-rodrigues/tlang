(* src/tdoc/tdoc_markdown.ml *)
(* Markdown generator for T-Doc *)

open Tdoc_types

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
      Printf.bprintf buf "- **%s**%s: %s\n" p.name type_str p.description
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
    List.iter (fun e -> Printf.bprintf buf "%s\n" e) entry.examples;
    Printf.bprintf buf "```\n\n";
  end;
  
  if entry.see_also <> [] then begin
    Printf.bprintf buf "## See Also\n\n";
    let links = List.map (fun s -> Printf.sprintf "[%s](%s.md)" s s) entry.see_also in
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
      Printf.bprintf buf "| [%s](%s.md) | %s |\n" e.name e.name e.description_brief
  ) (List.sort (fun a b -> String.compare a.name b.name) entries);
  
  Buffer.contents buf
