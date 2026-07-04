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

(** Read a pyproject.toml file and extract the requires-python field.
    Returns None if the file doesn't exist or can't be parsed. *)
let read_requires_python_from_workspace ~(root_dir : string) ~(workspace : string) : string option =
  let pyproject_path = Filename.concat (Filename.concat root_dir workspace) "pyproject.toml" in
  try
    let ch = open_in pyproject_path in
    let content =
      Fun.protect
        ~finally:(fun () -> close_in_noerr ch)
        (fun () -> really_input_string ch (in_channel_length ch))
    in
    let toml = Otoml.Parser.from_string content in
    let requires_python =
      try Some (Otoml.find toml Otoml.get_string ["project"; "requires-python"])
      with _ -> None
    in
    requires_python
  with _ -> None

(** Infer a Nixpkgs Python attribute name (e.g. "python312") from a PEP 440
    requires-python specifier in pyproject.toml.

    Handles these patterns:
      ==X.Y, ==X.Y.*, ~=X.Y, >=X.Y,<X.(Y+1)  → pythonXY
      >=X.Y  (no upper bound)                  → Error (ambiguous)
      >=X.Y,<X.Z where Z > Y+1                → Error (spans multiple minors)
      absent                                   → Error *)
let infer_py_version_from_requires_python (requires_python : string) : (string, string) result =
  let s = String.trim requires_python in
  (* Open-ended >= constraint with no upper bound — ambiguous *)
  let open_ended = Str.regexp "^>=\\([0-9]+\\)\\.\\([0-9]+\\)$" in
  if Str.string_match open_ended s 0 then
    let major = Str.matched_group 1 s in
    let minor = Str.matched_group 2 s in
    Error (Printf.sprintf "'requires-python' %S is ambiguous (open-ended upper bound). Set [py-dependencies].version explicitly in tproject.toml, or use a bounded specifier like '==%s.%s.*'"
      requires_python major minor)
  else begin
    (* Bounded >=X.Y,<X.Z constraint — must span exactly one minor *)
    let bounded = Str.regexp "^>=\\([0-9]+\\)\\.\\([0-9]+\\),<\\([0-9]+\\)\\.\\([0-9]+\\)$" in
    if Str.string_match bounded s 0 then
      let major = int_of_string (Str.matched_group 1 s) in
      let minor = int_of_string (Str.matched_group 2 s) in
      let ub_major = int_of_string (Str.matched_group 3 s) in
      let ub_minor = int_of_string (Str.matched_group 4 s) in
      if major = ub_major && ub_minor = minor + 1 then
        Ok (Printf.sprintf "python%d%d" major minor)
      else
        Error (Printf.sprintf "'requires-python' %S spans multiple minor versions; use a specifier that constrains to a single minor (e.g. '==%d.%d.*') or set [py-dependencies].version explicitly"
          requires_python major minor)
    else begin
      (* Compatible release ~=X.Y *)
      let compatible = Str.regexp "^~=\\([0-9]+\\)\\.\\([0-9]+\\)$" in
      if Str.string_match compatible s 0 then
        let major = int_of_string (Str.matched_group 1 s) in
        let minor = int_of_string (Str.matched_group 2 s) in
        Ok (Printf.sprintf "python%d%d" major minor)
      else begin
        (* Exact match: X.Y, ==X.Y, ==X.Y.* *)
        let exact = Str.regexp "^\\(==\\)?\\([0-9]+\\)\\.\\([0-9]+\\)\\(\\..*\\)?$" in
        if Str.string_match exact s 0 then
          let major = int_of_string (Str.matched_group 2 s) in
          let minor = int_of_string (Str.matched_group 3 s) in
          Ok (Printf.sprintf "python%d%d" major minor)
        else
          Error (Printf.sprintf "Could not parse 'requires-python' %S; expected a PEP 440 specifier (e.g. '==3.12', '~=3.12', '>=3.12,<3.13')" requires_python)
      end
    end
  end

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
        min_t_version = get_string_opt toml ["t"; "min_version"] ~default:Version.version;
        additional_tools = get_string_list_opt toml ["additional-tools"; "packages"] ~default:[];
        latex_packages = get_string_list_opt toml ["latex"; "packages"] ~default:[];
      }
  with
  | Otoml.Parse_error (_, msg) -> Error (Printf.sprintf "TOML parse error: %s" msg)
  | exn -> Error (Printf.sprintf "Failed to parse DESCRIPTION.toml: %s" (Printexc.to_string exn))

(** Parse git R package dependencies from [r-dependencies] (inline tables) *)
let parse_r_git_dependencies toml =
  try
    match Otoml.find toml Otoml.get_table ["r-dependencies"] with
    | pairs ->
      List.filter_map (fun (name, value) ->
        try
          let git_url = Otoml.find value Otoml.get_string ["git"] in
          let tag = Otoml.find value Otoml.get_string ["tag"] in
          Some { rgd_name = name; rgd_git_url = git_url; rgd_tag = tag }
        with _ -> None
      ) pairs
  with _ -> []

(** Parse a tproject.toml string into project_config.
    @param root_dir Optional root directory for reading pyproject.toml (needed when resolver=uv and version is absent). *)
let parse_tproject_toml ?(root_dir : string option) (content : string) : (project_config, string) result =
  try
    let toml = Otoml.Parser.from_string content in
    let name = get_string_opt toml ["project"; "name"] ~default:"" in
    if name = "" then Error "Missing required field: project.name"
    else
      let py_resolver = get_string_opt toml ["py-dependencies"; "resolver"] ~default:"nixpkgs" in
      let py_packages = get_string_list_opt toml ["py-dependencies"; "packages"] ~default:[] in
      if py_resolver <> "nixpkgs" && py_resolver <> "uv" then
        Error (Printf.sprintf "Unsupported [py-dependencies].resolver %S; expected \"nixpkgs\" or \"uv\"" py_resolver)
      else if py_resolver = "uv" && py_packages <> [] then
        Error "[py-dependencies].packages cannot be used when resolver = \"uv\"; declare Python dependencies in pyproject.toml and uv.lock instead"
      else
        let py_version_explicit =
          try Some (Otoml.find toml Otoml.get_string ["py-dependencies"; "version"])
          with _ -> None
        in
        let py_workspace = get_string_opt toml ["py-dependencies"; "workspace"] ~default:"python" in
        let py_version_res =
          match py_version_explicit with
          | Some v -> Ok v
          | None when py_resolver = "uv" ->
            (match root_dir with
             | Some dir ->
               (match read_requires_python_from_workspace ~root_dir:dir ~workspace:py_workspace with
                | Some rp ->
                  (match infer_py_version_from_requires_python rp with
                   | Ok v -> Ok v
                   | Error msg -> Error msg)
                | None -> Error (Printf.sprintf "Cannot infer [py-dependencies].version: pyproject.toml not found or missing 'requires-python' in workspace %S. Set [py-dependencies].version explicitly in tproject.toml." py_workspace))
             | None -> Error "Cannot infer [py-dependencies].version from UV workspace without a project root directory. Set [py-dependencies].version explicitly in tproject.toml.")
          | None -> Ok "python314"
        in
        match py_version_res with
        | Error msg -> Error msg
        | Ok py_version ->
            (* If version was explicitly set and we have a root_dir, warn if it conflicts with requires-python *)
            (match py_version_explicit, root_dir with
             | Some explicit_ver, Some dir when py_resolver = "uv" ->
               (match read_requires_python_from_workspace ~root_dir:dir ~workspace:py_workspace with
                | Some rp ->
                  (match infer_py_version_from_requires_python rp with
                   | Ok inferred when inferred <> explicit_ver ->
                     Printf.eprintf "Warning: tproject.toml sets [py-dependencies].version = %S but %S/pyproject.toml requires-python %S maps to %S. Using explicit version %S.\n%!"
                       explicit_ver py_workspace rp inferred explicit_ver
                   | _ -> ())
                | None -> ())
             | _ -> ());
            Ok {
              proj_name = name;
              proj_description = get_string_opt toml ["project"; "description"] ~default:"";
              proj_dependencies = parse_dependencies toml;
              proj_r_dependencies = get_string_list_opt toml ["r-dependencies"; "packages"] ~default:[];
              proj_r_git_dependencies = parse_r_git_dependencies toml;
              proj_py_dependencies = py_packages;
              proj_py_version = py_version;
              proj_py_resolver = py_resolver;
              proj_py_workspace = py_workspace;
              proj_julia_dependencies = get_string_list_opt toml ["jl-dependencies"; "packages"] ~default:[];
              proj_julia_version = get_string_opt toml ["jl-dependencies"; "version"] ~default:"lts";
              proj_visualization_tool = get_string_opt toml ["visualization-tool"; "command"] ~default:"";
              proj_min_t_version = get_string_opt toml ["t"; "min_version"] ~default:Version.version;
              proj_nixpkgs_date = get_string_opt toml ["nixpkgs"; "date"] ~default:"";
              proj_additional_tools = get_string_list_opt toml ["additional-tools"; "packages"] ~default:[];
              proj_latex_packages = get_string_list_opt toml ["latex"; "packages"] ~default:[];
              proj_license = get_string_opt toml ["license"; "name"] ~default:"";
              proj_authors = get_string_list_opt toml ["project"; "authors"] ~default:[];
            }
  with
  | Otoml.Parse_error (_, msg) -> Error (Printf.sprintf "TOML parse error: %s" msg)
  | Failure msg -> Error msg
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
  Printf.bprintf buf "\n[additional-tools]\n";
  Printf.bprintf buf "packages = [%s]\n"
    (String.concat ", " (List.map (fun a -> Printf.sprintf "%S" a) cfg.additional_tools));
  Printf.bprintf buf "\n[latex]\n";
  Printf.bprintf buf "packages = [%s]\n"
    (String.concat ", " (List.map (fun a -> Printf.sprintf "%S" a) cfg.latex_packages));
  Buffer.contents buf

(** Generate a tproject.toml string from project_config *)
let serialize_tproject_toml (cfg : project_config) : string =
  let buf = Buffer.create 512 in
  Buffer.add_string buf "[project]\n";
  Printf.bprintf buf "name = %S\n" cfg.proj_name;
  Printf.bprintf buf "description = %S\n" cfg.proj_description;
  Printf.bprintf buf "authors = [%s]\n"
    (String.concat ", " (List.map (fun a -> Printf.sprintf "%S" a) cfg.proj_authors));
  Buffer.add_char buf '\n';
  Buffer.add_string buf "[dependencies]\n";
  List.iter (fun dep ->
    Printf.bprintf buf "%s = { git = %S, tag = %S }\n"
      dep.dep_name dep.git_url dep.tag
  ) cfg.proj_dependencies;
  Buffer.add_char buf '\n';
  Buffer.add_string buf "[r-dependencies]\n";
  List.iter (fun g ->
    Printf.bprintf buf "%s = { git = %S, tag = %S }\n"
      g.rgd_name g.rgd_git_url g.rgd_tag
  ) cfg.proj_r_git_dependencies;
  Printf.bprintf buf "packages = [%s]\n\n"
    (String.concat ", " (List.map (fun a -> Printf.sprintf "%S" a) cfg.proj_r_dependencies));
  Buffer.add_string buf "[py-dependencies]\n";
  Printf.bprintf buf "version = %S\n" cfg.proj_py_version;
  if cfg.proj_py_resolver = "uv" then begin
    Printf.bprintf buf "resolver = %S\n" cfg.proj_py_resolver;
    Printf.bprintf buf "workspace = %S\n\n" cfg.proj_py_workspace
  end else
    Printf.bprintf buf "packages = [%s]\n\n"
      (String.concat ", " (List.map (fun a -> Printf.sprintf "%S" a) cfg.proj_py_dependencies));
  Buffer.add_string buf "[jl-dependencies]\n";
  Printf.bprintf buf "version = %S\n" cfg.proj_julia_version;
  Printf.bprintf buf "packages = [%s]\n\n"
    (String.concat ", " (List.map (fun a -> Printf.sprintf "%S" a) cfg.proj_julia_dependencies));
  if cfg.proj_visualization_tool <> "" then begin
    Buffer.add_string buf "[visualization-tool]\n";
    Printf.bprintf buf "command = %S\n\n" cfg.proj_visualization_tool
  end;
  Buffer.add_string buf "[additional-tools]\n";
  Printf.bprintf buf "packages = [%s]\n\n"
    (String.concat ", " (List.map (fun a -> Printf.sprintf "%S" a) cfg.proj_additional_tools));
  Buffer.add_string buf "[latex]\n";
  Printf.bprintf buf "packages = [%s]\n\n"
    (String.concat ", " (List.map (fun a -> Printf.sprintf "%S" a) cfg.proj_latex_packages));
  Buffer.add_string buf "[t]\n";
  Printf.bprintf buf "min_version = %S\n\n" cfg.proj_min_t_version;
  Printf.bprintf buf "[nixpkgs]\ndate = %S\n\n" cfg.proj_nixpkgs_date;
  if cfg.proj_license <> "" then begin
    Buffer.add_string buf "[license]\n";
    Printf.bprintf buf "name = %S\n" cfg.proj_license
  end;
  Buffer.contents buf
