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
