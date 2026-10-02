(* src/tdoc/tdoc_registry.ml *)
(* In-memory registry for documentation entries *)

open Tdoc_types

let registry : (string, doc_entry) Hashtbl.t = Hashtbl.create 100

(** Register a documentation entry in the in-memory registry.

    Duplicate names resolve deterministically, independent of parse
    order: an exported entry always beats an internal (@private) one,
    and otherwise the entry with more *parseable* signature info wins
    (a fully precise entry beats a partial one at the same count, so
    coverage counts cannot wobble with readdir order). Presence alone
    is not enough: more typed-but-garbled fields must never displace
    fewer good ones. Without this, same-name blocks (re-export stubs,
    OCaml-internal docs) shadow each other by readdir luck — flipping
    help() output, reference pages, and coverage counts between runs.
    Ties keep the first registration: a later entry with equal export
    status and rank is silently dropped, so re-registering a name
    (test seams, user `--#` blocks in `.t` files) never overrides the
    winner. Registration order itself is deterministic (sorted file
    walk), so winners are identical on every machine.

    @param entry The doc_entry to add. *)
let precise_type s =
  match s with
  | Some s -> (match Semantic_type.from_string s with
      | Semantic_type.TAny | Semantic_type.TUnknown -> false
      | _ -> true)
  | None -> false

let rank_entry (e : doc_entry) =
  let r = match e.return_value with
    | Some r -> precise_type r.type_info
    | None -> false
  in
  let ps = List.map (fun (p : param_doc) -> precise_type p.type_info) e.params in
  let full = r && List.for_all (fun x -> x) ps in
  ((if full then 1 else 0), List.length (List.filter (fun x -> x) (r :: ps)))

let register entry =
  let better new_ old_ =
    (new_.is_export && not old_.is_export)
    || ((new_.is_export = old_.is_export)
        && compare (rank_entry new_) (rank_entry old_) > 0)
  in
  match Hashtbl.find_opt registry entry.name with
  | None -> Hashtbl.replace registry entry.name entry
  | Some old -> if better entry old then Hashtbl.replace registry entry.name entry

(** Search the registry for a documentation entry by its function or symbol name.
    
    @param name The name of the symbol to find.
    @return [Some doc_entry] if found, otherwise [None]. *)
let lookup name =
  Hashtbl.find_opt registry name

(** Retrieve all registered documentation entries from the registry.
    
    @return A list of all registered doc_entry records. *)
let get_all () =
  Hashtbl.fold (fun _ v acc -> v :: acc) registry []

(** Snapshot the registry for save/restore around bulk loads. Tests that
    parse whole source trees (e.g. typing coverage audits) must not leak
    entries into other tests that assert pre-docs behavior. *)
let snapshot () =
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) registry []

let restore entries =
  Hashtbl.clear registry;
  List.iter (fun (k, v) -> Hashtbl.add registry k v) entries

(** Save all currently registered documentation entries to a JSON file.
    
    @param filename The destination file path. *)
let to_json_file filename =
  (* Exported entries only, like the reference pages and index: internal
     (@private) docs use OCaml-side vocabulary and must not shadow
     builtins here either (help() resolves by name). *)
  let entries =
    List.filter (fun e -> e.is_export) (get_all ())
  in
  let json = "{\"docs\": [" ^ (String.concat ", " (List.map doc_entry_to_json entries)) ^ "]}" in
  let chan = open_out filename in
  Fun.protect
    ~finally:(fun () -> close_out_noerr chan)
    (fun () -> output_string chan json)

(* Simple JSON parser (very limited) would go here for loading *)
(* For now, we only implement saving as loading is for the generation phase *)

(** Normalize a source file path to be correctly resolvable from the project workspace root.
    
    @param path The raw path to normalize.
    @return The normalized path. *)
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

(** Load documentation entries from a JSON file into the global registry.
    
    @param filename The source file path of the JSON documentation file. *)
let load_from_json filename =
  try
    let ch = open_in filename in
    let content =
      Fun.protect
        ~finally:(fun () -> close_in_noerr ch)
        (fun () -> really_input_string ch (in_channel_length ch))
    in
    
    let json = Tdoc_json.from_string content in
    match json with
    | `Assoc pairs ->
        (match List.assoc_opt "docs" pairs with
        | Some (`List docs) ->
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
  | Out_of_memory | Stack_overflow as e -> raise e
  | exn -> Printf.eprintf "Warning: Unknown error loading documentation: %s\n" (Printexc.to_string exn)
