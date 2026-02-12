(* src/tdoc/tdoc_types.ml *)
(* Data structures for T-Doc documentation system *)

type param_doc = {
  name : string;
  type_info : string option;
  description : string;
}

type intent_block = {
  purpose : string;
  use_when : string;
  alternatives : string option;
}

type return_doc = {
  type_info : string option;
  description : string;
}

type doc_entry = {
  name : string;
  description_brief : string;
  description_full : string;
  params : param_doc list;
  return_value : return_doc option;
  examples : string list;
  see_also : string list;
  family : string option;
  is_export : bool;
  intent : intent_block option;
  package : string option;
  source_path : string;
  line_number : int;
}

(* JSON Serialization (manual implementation for now to avoid ppx dependencies) *)
let json_escape s =
  let buf = Buffer.create (String.length s + 10) in
  String.iter (fun c ->
    match c with
    | '"' -> Buffer.add_string buf "\\\""
    | '\\' -> Buffer.add_string buf "\\\\"
    | '\n' -> Buffer.add_string buf "\\n"
    | '\r' -> Buffer.add_string buf "\\r"
    | '\t' -> Buffer.add_string buf "\\t"
    | c -> Buffer.add_char buf c
  ) s;
  Buffer.contents buf

let param_to_json (p : param_doc) =
  Printf.sprintf "{\"name\": \"%s\", \"type\": \"%s\", \"description\": \"%s\"}"
    (json_escape p.name)
    (json_escape (Option.value ~default:"" p.type_info))
    (json_escape p.description)

let string_list_to_json l =
  "[" ^ (String.concat ", " (List.map (fun s -> "\"" ^ json_escape s ^ "\"") l)) ^ "]"

let doc_entry_to_json entry =
  let params_json = "[" ^ (String.concat ", " (List.map param_to_json entry.params)) ^ "]" in
  let return_json = match entry.return_value with
    | Some r -> Printf.sprintf "{\"type\": \"%s\", \"description\": \"%s\"}" 
                  (json_escape (Option.value ~default:"" r.type_info)) 
                  (json_escape r.description)
    | None -> "null"
  in
  let intent_json = match entry.intent with
    | Some i -> Printf.sprintf "{\"purpose\": \"%s\", \"use_when\": \"%s\", \"alternatives\": \"%s\"}"
                  (json_escape i.purpose) (json_escape i.use_when) 
                  (json_escape (Option.value ~default:"" i.alternatives))
    | None -> "null"
  in
  Printf.sprintf 
    "{\"name\": \"%s\", \"brief\": \"%s\", \"full\": \"%s\", \"params\": %s, \"return\": %s, \"examples\": %s, \"see_also\": %s, \"family\": \"%s\", \"export\": %b, \"intent\": %s, \"package\": \"%s\", \"source\": \"%s\", \"line\": %d}"
    (json_escape entry.name)
    (json_escape entry.description_brief)
    (json_escape entry.description_full)
    params_json
    return_json
    (string_list_to_json entry.examples)
    (string_list_to_json entry.see_also)
    (json_escape (Option.value ~default:"" entry.family))
    entry.is_export
    intent_json
    (json_escape (Option.value ~default:"" entry.package))
    (json_escape entry.source_path)
    entry.line_number
