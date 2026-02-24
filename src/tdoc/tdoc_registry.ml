(* src/tdoc/tdoc_registry.ml *)
(* In-memory registry for documentation entries *)

open Tdoc_types

let registry : (string, doc_entry) Hashtbl.t = Hashtbl.create 100

let register entry =
  Hashtbl.replace registry entry.name entry

let lookup name =
  Hashtbl.find_opt registry name

let get_all () =
  Hashtbl.fold (fun _ v acc -> v :: acc) registry []

let to_json_file filename =
  let entries = get_all () in
  let json = "{\"docs\": [" ^ (String.concat ", " (List.map doc_entry_to_json entries)) ^ "]}" in
  let chan = open_out filename in
  output_string chan json;
  close_out chan

(* Simple JSON parser (very limited) would go here for loading *)
(* For now, we only implement saving as loading is for the generation phase *)

let normalize_path path =
  if Sys.file_exists path then path
  else
    (* Try to resolve relative to current project if it contains /src/ *)
    let parts = String.split_on_char '/' path in
    let rec find_src = function
      | [] -> None
      | "src" :: rest -> Some (String.concat "/" ("src" :: rest))
      | _ :: rest -> find_src rest
    in
    match find_src parts with
    | Some rel -> if Sys.file_exists rel then rel else path
    | None -> path

let load_from_json filename =
  try
    let ch = open_in filename in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    
    let json = Tdoc_json.from_string content in
    match json with
    | Tdoc_json.JObject pairs ->
        (match List.assoc_opt "docs" pairs with
        | Some (Tdoc_json.JArray docs) ->
            List.iter (fun doc_json ->
              let entry = Tdoc_types.doc_entry_of_json doc_json in
              let normalized_entry = { entry with source_path = normalize_path entry.source_path } in
              register normalized_entry
            ) docs
        | _ -> Printf.eprintf "Warning: Invalid docs.json format (missing 'docs' array)\n")
    | _ -> Printf.eprintf "Warning: Invalid docs.json format (not an object)\n"
  with
  | Sys_error msg -> Printf.eprintf "Warning: Could not load documentation: %s\n" msg
  | Tdoc_json.Json_error msg -> Printf.eprintf "Warning: Failed to parse documentation: %s\n" msg
  | _ -> Printf.eprintf "Warning: Unknown error loading documentation\n"
