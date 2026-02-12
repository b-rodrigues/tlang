(* src/package_manager/toml_parser.ml *)
(* TOML parsing for DESCRIPTION.toml and tproject.toml using otoml *)

open Package_types

(** Helper: get a string from a TOML table, with a default *)
let get_string_opt toml path ~default =
  try Otoml.find toml Otoml.get_string path
  with _ -> default

(** Helper: get a string list from a TOML table, with a default *)
let get_string_list_opt toml path ~default =
  try Otoml.find toml (Otoml.get_array Otoml.get_string) path
  with _ -> default

(** Parse dependencies from [dependencies] table *)
let parse_dependencies toml =
  try
    match Otoml.find toml Otoml.get_table ["dependencies"] with
    | pairs ->
      List.filter_map (fun (name, value) ->
        try
          let git_url = Otoml.find value Otoml.get_string ["git"] in
          let tag = Otoml.find value Otoml.get_string ["tag"] in
          Some { dep_name = name; git_url; tag }
        with _ -> None
      ) pairs
  with _ -> []

(** Parse a DESCRIPTION.toml string into package_config *)
let parse_description_toml (content : string) : (package_config, string) result =
  try
    let toml = Otoml.Parser.from_string content in
    let name = get_string_opt toml ["package"; "name"] ~default:"" in
    if name = "" then Error "Missing required field: package.name"
    else
      Ok {
        name;
        version = get_string_opt toml ["package"; "version"] ~default:"0.1.0";
        description = get_string_opt toml ["package"; "description"] ~default:"";
        authors = get_string_list_opt toml ["package"; "authors"] ~default:[];
        license = get_string_opt toml ["package"; "license"] ~default:"EUPL-1.2";
        homepage = get_string_opt toml ["package"; "homepage"] ~default:"";
        repository = get_string_opt toml ["package"; "repository"] ~default:"";
        dependencies = parse_dependencies toml;
        min_t_version = get_string_opt toml ["t"; "min_version"] ~default:"0.5.0";
      }
  with
  | Otoml.Parse_error (_, msg) -> Error (Printf.sprintf "TOML parse error: %s" msg)
  | exn -> Error (Printf.sprintf "Failed to parse DESCRIPTION.toml: %s" (Printexc.to_string exn))

(** Parse a tproject.toml string into project_config *)
let parse_tproject_toml (content : string) : (project_config, string) result =
  try
    let toml = Otoml.Parser.from_string content in
    let name = get_string_opt toml ["project"; "name"] ~default:"" in
    if name = "" then Error "Missing required field: project.name"
    else
      Ok {
        proj_name = name;
        proj_description = get_string_opt toml ["project"; "description"] ~default:"";
        proj_dependencies = parse_dependencies toml;
        proj_min_t_version = get_string_opt toml ["t"; "min_version"] ~default:"0.5.0";
      }
  with
  | Otoml.Parse_error (_, msg) -> Error (Printf.sprintf "TOML parse error: %s" msg)
  | exn -> Error (Printf.sprintf "Failed to parse tproject.toml: %s" (Printexc.to_string exn))

(** Generate a DESCRIPTION.toml string from package_config *)
let serialize_description_toml (cfg : package_config) : string =
  let buf = Buffer.create 512 in
  Buffer.add_string buf "[package]\n";
  Printf.bprintf buf "name = %S\n" cfg.name;
  Printf.bprintf buf "version = %S\n" cfg.version;
  Printf.bprintf buf "description = %S\n" cfg.description;
  Printf.bprintf buf "authors = [%s]\n"
    (String.concat ", " (List.map (fun a -> Printf.sprintf "%S" a) cfg.authors));
  Printf.bprintf buf "license = %S\n" cfg.license;
  if cfg.homepage <> "" then Printf.bprintf buf "homepage = %S\n" cfg.homepage;
  if cfg.repository <> "" then Printf.bprintf buf "repository = %S\n" cfg.repository;
  Buffer.add_char buf '\n';
  Buffer.add_string buf "[dependencies]\n";
  List.iter (fun dep ->
    Printf.bprintf buf "%s = { git = %S, tag = %S }\n"
      dep.dep_name dep.git_url dep.tag
  ) cfg.dependencies;
  Buffer.add_char buf '\n';
  Buffer.add_string buf "[t]\n";
  Printf.bprintf buf "min_version = %S\n" cfg.min_t_version;
  Buffer.contents buf

(** Generate a tproject.toml string from project_config *)
let serialize_tproject_toml (cfg : project_config) : string =
  let buf = Buffer.create 512 in
  Buffer.add_string buf "[project]\n";
  Printf.bprintf buf "name = %S\n" cfg.proj_name;
  Printf.bprintf buf "description = %S\n" cfg.proj_description;
  Buffer.add_char buf '\n';
  Buffer.add_string buf "[dependencies]\n";
  List.iter (fun dep ->
    Printf.bprintf buf "%s = { git = %S, tag = %S }\n"
      dep.dep_name dep.git_url dep.tag
  ) cfg.proj_dependencies;
  Buffer.add_char buf '\n';
  Buffer.add_string buf "[t]\n";
  Printf.bprintf buf "min_version = %S\n" cfg.proj_min_t_version;
  Buffer.contents buf
